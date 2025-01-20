#!/bin/bash

# This script queries the Gene Expression Atlas (GXA) API to retrieve information about human 
# bulk RNA-seq experiments with disease associations from patient samples (excluding cell lines). 
# It processes the data to extract relevant details and saves the output to a file.

GXA='https://www.ebi.ac.uk/gxa/json/experiments';

if ! command -v jq &> /dev/null
then
    echo "jq is not installed. Please install jq to proceed"
    exit 1
fi

echo -e "accession\torganism\texp_type\tdiseases\torganism_parts_combined\traw_counts_file\tdescription" > output.tsv

experiment_accessions=($(curl -sS $GXA | jq -r '.experiments[].experimentAccession' | sort -u)); 

for accession in "${experiment_accessions[@]}"; do
    echo "accession: $accession"
    GXAexp="https://www.ebi.ac.uk/gxa/json/experiments/$accession"
    
    organism=$(curl -sS "$GXAexp" | jq -r '.experiment.species')
    echo "organism: $organism"
    if [[ $organism == "Homo sapiens" ]]; then
        echo "Human experiment"
    else
        echo "Not human experiment"
        continue
    fi
    
    exp_type=$(curl -sS $GXAexp | jq '.experiment.type' | sed 's/"//g' )
    echo "Atlas experiment type: $exp_type"


    if [[ "$exp_type" == "rnaseq_mrna_baseline" ]]; then
        # first we check this is not cell line
        cell_lines=$(curl -sS "$GXAexp" | jq '.columnHeaders[] | select(.assayGroupSummary.properties[] | (.propertyName == "cell line" and .contrastPropertyType == "FACTOR")) | .assayGroupSummary.properties[] | select(.propertyName == "cell line") | .testValue' | sort -u | wc -l)
        if [[ $cell_lines -ne 0 ]]; then
            continue  
        else
            echo "No cell lines"
        fi

        # Matches of FACTOR "disease" in a case-insensitive manner ("i" flag)
        # filter out experiments where all the 'disease' values are 'normal' or na
        diseases=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].assayGroupSummary.properties[] | select(.propertyName | test("disease"; "i")) | .testValue | select(. != "normal" and . != "" and . != ",normal")' | sort -u | paste -sd "," -)
        ndiseases=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].assayGroupSummary.properties[] | select(.propertyName | test("disease"; "i")) | .testValue | select(. != "normal" and . != "" and . != ",normal")'  | sort -u | wc -l)

        # if not empty, we have a disease-related experiment
        if [[ $ndiseases -ne 0 ]]; then
            organism_parts=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].assayGroupSummary.properties[] | select(.propertyName == "organism part") | .testValue' | sort -u | paste -sd "," -)
            organism_parts_combined=$(echo "$organism_parts" | tr '\n' ',' | sed 's/,$//')
            description=$(curl -sS "$GXAexp" | jq -r '.experiment.description')
            raw_counts_file="http://ftp.ebi.ac.uk/pub/databases/microarray/data/atlas/experiments/$accession/$accession-raw-counts.tsv"
            echo -e "$accession\t$organism\t$exp_type\t$diseases\t$organism_parts_combined\t$raw_counts_file\t$description" >> output.tsv
        fi

    elif [[ "$exp_type" == "rnaseq_mrna_differential" ]]; then

        # first we check this is not cell line
        cell_lines=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].contrastSummary.properties[] | select(.propertyName | test("cell line"; "i")) | .testValue' | sort -u | wc -l)
        if [[ $cell_lines -ne 0 ]]; then
            continue  
        else
            echo "No cell lines"
        fi

        # Matches of FACTOR "disease" in a case-insensitive manner ("i" flag)
        # filter out experiments where all the 'disease' values are 'normal' or na
        diseases=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].contrastSummary.properties[] | select(.propertyName | test("disease"; "i")) | .testValue | select(. != "normal" and . != "" and . != ",normal")' | sort -u | paste -sd "," -)
        ndiseases=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].contrastSummary.properties[] | select(.propertyName | test("disease"; "i")) | .testValue | select(. != "normal" and . != "" and . != ",normal")' | sort -u | wc -l)

        # if not empty, we have a disease match
        if [[ $ndiseases -ne 0 ]]; then
            organism_parts=$(curl -sS "$GXAexp" | jq -r '.columnHeaders[].contrastSummary.properties[] | select(.propertyName | ascii_downcase == "organism part") | .testValue' | sort -u )
            organism_parts_combined=$(echo "$organism_parts" | tr '\n' ',' | sed 's/,$//')
            description=$(curl -sS "$GXAexp" | jq -r '.experiment.description')
            raw_counts_file="http://ftp.ebi.ac.uk/pub/databases/microarray/data/atlas/experiments/$accession/$accession-raw-counts.tsv"
            echo -e "$accession\t$organism\t$exp_type\t$diseases\t$organism_parts_combined\t$raw_counts_file\t$description" >> output.tsv
        fi
    else
        echo "not a human rna-seq experiment"
    fi
done

