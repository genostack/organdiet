#!/usr/bin/env nextflow

/*
========================================================================================
                                      OrganDiet
========================================================================================
 OrganDiet: Metagenomics human Diet analysis pipeline. Started January 2018
#### Homepage / Documentation
https://github.com/maxibor/organdiet
#### Authors
 Maxime Borry <maxime.borry@gmail.com>
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
Pipeline overview:
 - 1:   FastQC for raw sequencing reads quality control
 - 2:   AdapterRemoval for read trimming and cleaning, and if specified (--adna), merging.
 - 3:   Build Bowtie DB of control. If control provided.
 - 4:   Align on control, output unaligned reads. If control provided.
 - 5:   Align on human genome, output unaligned reads
 - 6:   Align on organellome database
 - 7:   Extract Mapped reads
 - 8:   Filter reads on quality and length
 - 9:   Align on NR/NT database
 - 10:  Assign LCA - Krona output
 - 11:  Generate MultiQC run summary
 ----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info"""
    =========================================
     OrganDiet version ${version}
     Last updated on ${version_date}
    =========================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run maxibor/organdiet --reads '*_R{1,2}.fastq.gz'
    Mandatory arguments:
      --reads                       Path to input data (must be surrounded with quotes)

    Options:
      --singleEnd                   Specifies that the input is single end reads (true | false). Defaults to ${params.singleEnd}. Only available for aDNA reads samples.
      --ctrl                        Specifies control fastq sequencing data. Must be the same specified the same way as --reads. Defaults to ${params.ctrl}
      --phred                       Specifies the Fastq PHRED quality encoding (33 | 64 | solexa). Defaults to 33.
      --aligner2                    Specifies the 2nd aligner to nt or nr db (respectively centrifuge or diamond). The proper db associated with aligner2 program must be specified. Defaults to ${params.aligner2}
      --adna                        Specifies if you have ancient dna (true) or modern dna (false). Defaults to ${params.adna}
      --bastamode                   Specifies the mode of LCA for BASTA. Only used if --aligner2 is set to diamond. Defaults to ${params.bastamode}
      --bastaid                     Specifies the identity lower threshold for BASTA LCA. Only used if --aligner2 is set to diamond. Defaults to ${params.bastaid}
      --bastanum                    Specifies the number of hits to retain for BASTA LCA. Only used if --aligner2 is set to diamond. Defaults to ${params.bastanum}
      --trimmingCPU                 Specifies the number of CPU used to trimming/cleaning by AdapterRemoval. Defaults to ${params.trimmingCPU}
      --bowtieCPU                   Specifies the number of CPU used by bowtie2 aligner. Defaults to ${params.bowtieCPU}
      --diamondCPU                  Specifies the number of CPU used by diamond aligner. Only used if --aligner2 is set to diamond. Defaults to ${params.diamondCPU}
      --centrifugeCPU               Specifies the number of CPU used by centrifuge aligner. Only used if --aligner2 is set to centrifuge. Default to ${params.centrifugeCPU}

    References: (files and directories must exist if used)
      --btindex                     Path to organellome database bowtie2 index. Defaults to ${params.btindex}
      --hgindex                     Path to human genome bowtie2 index. Defaults to ${params.hgindex}
      --nrdb                        Path to diamond nr db index. Used if --aligner2 is set to diamond. Defaults to ${params.nrdb}
      --bastadb                     Path to recentrifuge taxonomy db. Must be specified if --aligner2 is centrifuge. Defaults to ${params.bastadb}
      --centrifugedb                Path to centrifuge nt db index. Used if --aligner2 is set to centrifuge. Defaults to ${params.centrifugedb}

    Other options:
      --results                     Name of result directory. Defaults to ${params.results}

    """.stripIndent()
}

//Pipeline version
version = "0.2.5"
version_date = "March 22nd, 2018"

params.reads = "*_{1,2}.fastq.gz"
params.ctrl = "none"


// Result directory
params.results = "$PWD/results"

// Script and configurations
params.singleEnd = false
params.adna = true
params.phred = 33
params.multiqc_conf="$baseDir/conf/.multiqc_config.yaml"
params.aligner2 = "diamond"
scriptdir = "$baseDir/bin/"
py_specie = scriptdir+"process_mapping.py"
centrifuge2krona=scriptdir+"centrifuge2krona"
recentrifuge = scriptdir+"recentrifuge/recentrifuge.py"
basta = scriptdir+"BASTA/bin/basta"
basta2krona = scriptdir+"BASTA/scripts/basta2krona.py"

// Databases locations
params.btindex = "$baseDir/organellome_db/organellome"
params.hgindex = "$baseDir/hs_genome/Homo_sapiens_Ensembl_GRCh37/Homo_sapiens/Ensembl/GRCh37/Sequence/Bowtie2Index/genome"
params.nrdb = "$baseDir/nr_diamond_db/nr"
params.centrifugedb = "$baseDir/nt_db/nt"
params.bastadb = "$baseDir/taxonomy"

// BASTA (LCA) parameters
params.bastamode = "majority"
params.bastaid = 99
params.bastanum = 5

//CPU parameters
params.trimmingCPU = 12
params.bowtieCPU = 18
params.diamondCPU = 18
params.centrifugeCPU = 18

// Show help emssage
params.help = false
params.h = false
if (params.help || params.h){
    helpMessage()
    exit 0
}



// Header log info
log.info "========================================="
log.info " OrganDiet version ${version}"
log.info " Last updated on ${version_date}"
log.info "========================================="
def summary = [:]
summary['Reads']        = params.reads
if (params.ctrl) summary['Control']    = params.ctrl
summary['DNA type']    = params.adna ? 'Ancient DNA' : 'Modern DNA'
summary['PHRED'] = params.phred
summary['Organellome database']   = params.btindex
summary['Human genome']     = params.hgindex
summary['Aligner2'] = params.aligner2
if (params.aligner2 == "diamond") summary['Diamond DB'] = params.nrdb
if (params.aligner2 == "centrifuge") summary['Centrifuge DB']  = params.centrifugedb
if (params.aligner2 == "diamond"){
    summary["BASTA mode"] = params.bastamode
    summary["BASTA identity threshold"] = params.bastaid
    summary["BASTA hit threshold"] = params.bastanum
}
summary["CPU for Trimming"] = params.trimmingCPU
summary["CPU for Bowtie2"] = params.bowtieCPU
if (params.aligner2 == "diamond") summary["CPU for diamond"] = params.diamondCPU
if (params.aligner2 == "centrifuge") summary["CPU for centrifuge"] = params.centrifugeCPU
summary["Results directory path"] = params.results
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="


PHRED = Integer.toString(params.phred)
btquality = "--phred"+PHRED+"-quals"

//Check for singleEnd ancientDNA sanity

if (params.singleEnd == true && params.adna != true){
    exit 1, "Single End mode is only available for ancient DNA samples"
}

Channel
    .fromFilePairs( params.reads, size: params.singleEnd ? 1 : 2 )
    .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nIf this is single-end data, please specify --singleEnd on the command line." }
	.into { raw_reads_fastqc; raw_reads_trimming }

if (params.ctrl != "none"){
    Channel
        .fromFilePairs(params.ctrl, size: 2)
        .ifEmpty { exit 1, "Cannot find any reads matching: ${params.ctrl}\n Please note that single-end data is not supported for the control."}
        .into { raw_ctrl_fastqc; raw_ctrl_trimming }

}


/*
* STEP 1 - FastQC
*/
process fastqc {
    tag "$name"

    publishDir "${params.results}/fastqc", mode: 'copy',
       saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

    input:
        set val(name), file(reads) from raw_reads_fastqc

    output:
        file '*_fastqc.{zip,html}' into fastqc_results
        file '.command.out' into fastqc_stdout

    script:
        """
        fastqc -q $reads
        """
}

if (params.ctrl != "none"){
    process fastqc_control {
        tag "$name"

        publishDir "${params.results}/fastqc", mode: 'copy',
           saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

        input:
            set val(name), file(reads) from raw_ctrl_fastqc

        script:
            """
            fastqc -q $reads
            """
    }
}


/*
 * STEP 2 - AdapterRemoval
 */


if (params.adna == true){

    if (params.singleEnd == true){
        process adapter_removal_ancient_dna_SE {
            tag "$name"

            cpus = params.trimmingCPU

            publishDir "${params.results}/trimmed", mode: 'copy'

            input:
                set val(name), file(reads) from raw_reads_trimming

            output:
                set val(name), file('*.truncated.fastq') into trimmed_reads
                set val(name), file("*.settings") into adapter_removal_results
                file '*_fastqc.{zip,html}' into fastqc_results_after_trim

            script:
                outSE = name+".truncated.fastq"
                """
                AdapterRemoval --basename $name --file1 ${reads[0]} --trimns --trimqualities --output1 $outSE --threads ${task.cpus} --qualitybase $PHRED
                fastqc -q *.truncated*
                """
        }
    } else {
        process adapter_removal_ancient_dna_PE {
            tag "$name"

            cpus = params.trimmingCPU

            publishDir "${params.results}/trimmed", mode: 'copy'

            input:
                set val(name), file(reads) from raw_reads_trimming

            output:
                set val(name), file('*.collapsed.fastq') into trimmed_reads
                set val(name), file("*.settings") into adapter_removal_results
                file '*_fastqc.{zip,html}' into fastqc_results_after_trim

            script:
                out1 = name+".pair1.discarded.fastq"
                out2 = name+".pair2.discarded.fastq"
                col_out = name+".collapsed.fastq"
                """
                AdapterRemoval --basename $name --file1 ${reads[0]} --file2 ${reads[1]} --trimns --trimqualities --collapse --output1 $out1 --output2 $out2 --outputcollapsed $col_out --threads ${task.cpus} --qualitybase $PHRED
                fastqc -q *.collapsed*
                """
        }
    }



    if (params.ctrl != "none"){
        process adapter_removal_ctrl_ancient_dna {
            tag "$name"

            cpus = params.trimmingCPU

            publishDir "${params.results}/trimmed", mode: 'copy'

            input:
                set val(name), file(reads) from raw_ctrl_trimming

            output:
                set val(name), file('*.collapsed.fastq') into collapsed_reads_ctrl
                set val(name), file(out1), file(out2) into truncated_reads_ctrl


            script:
                out1 = name+".pair1.truncated.fastq"
                out2 = name+".pair2.truncated.fastq"
                col_out = name+".collapsed.fastq"
                """
                AdapterRemoval --basename $name --file1 ${reads[0]} --file2 ${reads[1]} --trimns --trimqualities --collapse --output1 $out1 --output2 $out2 --outputcollapsed $col_out --threads ${task.cpus} --qualitybase $PHRED
                """
        }
    }
} else {
    process adapter_removal_modern_dna {
        tag "$name"

        cpus = params.trimmingCPU

        publishDir "${params.results}/trimmed", mode: 'copy'

        input:
            set val(name), file(reads) from raw_reads_trimming

        output:
            set val(name), file(out1), file(out2) into truncated_reads
            set val(name), file("*.settings") into adapter_removal_results
            file '*_fastqc.{zip,html}' into fastqc_results_after_trim



        script:
            out1 = name+".pair1.truncated.fastq"
            out2 = name+".pair2.truncated.fastq"
            """
            AdapterRemoval --basename $name --file1 ${reads[0]} --file2 ${reads[1]} --trimns --trimqualities --output1 $out1 --output2 $out2 --threads ${task.cpus} --qualitybase $PHRED
            fastqc -q *.truncated*
            """
    }

    if (params.ctrl != "none"){
        process adapter_removal_ctrl_modern_dna {
            tag "$name"

            cpus = params.trimmingCPU

            publishDir "${params.results}/trimmed", mode: 'copy'

            input:
                set val(name), file(reads) from raw_ctrl_trimming

            output:
                set val(name), file(out1), file(out2) into truncated_reads_ctrl

            script:
                out1 = name+".pair1.truncated.fastq"
                out2 = name+".pair2.truncated.fastq"
                """
                AdapterRemoval --basename $name --file1 ${reads[0]} --file2 ${reads[1]} --trimns --trimqualities --output1 $out1 --output2 $out2 --threads ${task.cpus} --qualitybase $PHRED
                """
        }
    }
}





/*
* STEP 3 - Build Bowtie DB of control
*/
if (params.adna == true){
    if (params.ctrl != "none"){
        process ctr_bowtie_db_ancient_dna {
            cpus = params.bowtieCPU

            input:
                set val(name), file(col_read) from collapsed_reads_ctrl

            output:
                file "ctrl_index*" into ctrl_index

            script:
                """
                sed '/^@/!d;s//>/;N' $col_read > ctrl.fa
                bowtie2-build --threads ${task.cpus} ctrl.fa ctrl_index
                """
        }
    }
} else {
    if (params.ctrl != "none"){
        process ctr_bowtie_db_modern_dna {
            cpus = params.bowtieCPU

            input:
                set val(name), file(trun_read1), file(trun_read2) from truncated_reads_ctrl

            output:
                file "ctrl_index*" into ctrl_index

            script:
                merge_file = name+"_merged.fq"
                """
                cat ${trun_read1} > $merge_file
                cat ${trun_read2} >> $merge_file
                sed '/^@/!d;s//>/;N' $merge_file > ctrl.fa
                bowtie2-build --threads ${task.cpus} ctrl.fa ctrl_index
                """

        }
    }

}





/*
* STEP 4 - Align on control, output unaligned reads
*/

if (params.adna == true){
    if (params.ctrl != "none"){
        process bowtie_align_to_ctrl_ancient_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/control_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
                set val(name), file(col_reads) from trimmed_reads
                file bt_index from ctrl_index.collect()

            output:
                set val(name), file('*.unal.fastq') into fq_unaligned_ctrl_reads
                file("*.metrics") into ctrl_aln_metrics

            script:
                sam_out = name+".sam"
                fq_out = name+".unal.fastq"
                metrics = name+".metrics"
                quality = "--phred "+PHRED
                """
                bowtie2 -x ctrl_index -U $col_reads --no-sq --threads ${task.cpus} $btquality --un $fq_out 2> $metrics
                """

        }
    }
} else {
    if (params.ctrl != "none"){
        process bowtie_align_to_ctrl_modern_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/control_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
                set val(name), file(trun_read1), file(trun_read2) from truncated_reads
                file bt_index from ctrl_index.collect()

            output:
                file("*.metrics") into ctrl_aln_metrics
                set val(name), file(out1), file(out2) into fq_unaligned_ctrl_reads

            script:
                sam_out = name+".sam"
                fq_out = name+".unal.fastq"
                out1=name+".unal.1.fastq"
                out2=name+".unal.2.fastq"
                metrics = name+".metrics"
                """
                bowtie2 -x ctrl_index -1 $trun_read1 -2 $trun_read2 --no-sq $btquality --threads ${task.cpus} --un-conc $fq_out 2> $metrics
                """

        }
    }

}





/*
* STEP 5 - Align on human genome, output unaligned reads
*/

if (params.ctrl != "none"){
    if (params.adna == true){
        process bowtie_align_to_human_genome_from_ctrl_ancient_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/human_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
                set val(name), file(reads) from fq_unaligned_ctrl_reads

            output:
                set val(name), file('*.human_unal.fastq') into fq_unaligned_human_reads
                file("*.metrics") into human_aln_metrics

            script:
                fq_out = name+".human_unal.fastq"
                metrics = name+".metrics"
                """
                bowtie2 -x ${params.hgindex} -U $reads --no-sq $btquality --threads ${task.cpus} --un $fq_out --end-to-end --very-fast 2> $metrics
                """

        }
    } else {
        process bowtie_align_to_human_genome_from_ctrl_modern_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/human_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
                set val(name), file(trun_read1), file(trun_read2) from fq_unaligned_ctrl_reads

            output:
                set val(name), file(out1), file(out2) into fq_unaligned_human_reads
                file("*.metrics") into human_aln_metrics

            script:
                fq_out = name+".human_unal.fastq"
                out1 = name+".human_unal.1.fastq"
                out2 = name+".human_unal.2.fastq"
                metrics = name+".metrics"
                """
                bowtie2 -x ${params.hgindex} -1 $trun_read1 -2 $trun_read2 --no-sq $btquality --threads ${task.cpus} --un-conc $fq_out --end-to-end --very-fast 2> $metrics
                """

        }
    }

} else {
    if (params.adna == true){
        process bowtie_align_to_human_genome_no_control_ancient_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/human_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
            set val(name), file(col_reads) from trimmed_reads

            output:
                set val(name), file('*.human_unal.fastq') into fq_unaligned_human_reads
                file("*.metrics") into human_aln_metrics

            script:
                fq_out = name+".human_unal.fastq"
                metrics = name+".metrics"
                """
                bowtie2 -x ${params.hgindex} -U $col_reads --no-sq $btquality --threads ${task.cpus} --un $fq_out --end-to-end --very-fast 2> $metrics
                """


        }
    } else {
        process bowtie_align_to_human_genome_no_control_modern_dna {
            tag "$name"

            cpus = params.bowtieCPU

            publishDir "${params.results}/human_removed", mode: 'copy',
                saveAs: {filename ->
                    if (filename.indexOf(".fastq") > 0)  "./$filename"
                }

            input:
                set val(name), file(trun_read1), file(trun_read2) from truncated_reads

            output:
                set val(name), file(out1), file(out2) into fq_unaligned_human_reads
                file("*.metrics") into human_aln_metrics

            script:
                fq_out = name+".human_unal.fastq"
                out1 = name+".human_unal.1.fastq"
                out2 = name+".human_unal.2.fastq"
                metrics = name+".metrics"
                """
                bowtie2 -x ${params.hgindex} -1 $trun_read1 -2 $trun_read2 --no-sq $btquality --threads ${task.cpus} --un-conc $fq_out --end-to-end --very-fast 2> $metrics
                """
        }
    }

}







/*
* STEP 6 - Align on organellome database
*/

if (params.adna == true ){
    process bowtie_align_to_organellome_db_ancient_dna {
        tag "$name"

        cpus = params.bowtieCPU

        publishDir "${params.results}/alignments", mode: 'copy',
            saveAs: {filename ->
                if (filename.indexOf(".sam") > 0)  "./$filename"
            }

        input:
            set val(name), file(reads) from fq_unaligned_human_reads

        output:
            set val(name), file('*.sam') into aligned_reads
            file("*.metrics") into organellome_aln_metrics

        script:
            sam_out = name+".sam"
            metrics = name+".metrics"
            """
            bowtie2 -x ${params.btindex} -U $reads --end-to-end $btquality --threads ${task.cpus} -S $sam_out -a 2> $metrics
            """

    }
} else {
    process bowtie_align_to_organellome_db_modern_dna {
        tag "$name"

        cpus = params.bowtieCPU

        publishDir "${params.results}/alignments", mode: 'copy',
            saveAs: {filename ->
                if (filename.indexOf(".sam") > 0)  "./$filename"
            }

        input:
            set val(name), file(read1), file(read2) from fq_unaligned_human_reads

        output:
            set val(name), file('*.sam') into aligned_reads
            file("*.metrics") into organellome_aln_metrics

        script:
            sam_out = name+".sam"
            metrics = name+".metrics"
            """
            bowtie2 -x ${params.btindex} -1 $read1 -2 $read2 --end-to-end $btquality --threads ${task.cpus} -S $sam_out -a 2> $metrics
            """
    }
}


/*
* STEP 7 - Extract Mapped reads
*/

process extract_mapped_reads {
    tag "$name"

    publishDir "${params.results}/alignments", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf(".mapped.sam") > 0)  "./$filename"
        }

    input:
        set val(name), file(align) from aligned_reads

    output:
        set val(name), file('*.mapped.sam') into mapped_reads

    script:
        mapped_out = name+".mapped.sam"
        """
        samtools view -S -F4 $align > $mapped_out
        """
}

/*
* STEP 8 - Filter reads on quality and length
*/

process extract_best_reads {
    tag "$name"

    input:
        set val(name), file(sam) from mapped_reads

    output:
        set val(name), file("*.best.aligned.fa") into best_match

    script:
        """
        python $py_specie $sam
        """
}

/*
* STEP 9 - Align on NR/NT database
*/

if (params.aligner2 == "diamond"){
    process diamond_align_to_nr {
        tag "$name"

        cpus = params.diamondCPU

        publishDir "${params.results}/nr_alignment", mode: 'copy',
            saveAs: {filename ->  "./$filename"}

        input:
            set val(name), file(best_fa) from best_match

        output:
            set val(name), file("*.diamond.out") into nr_aligned

        script:
            diamond_out = name+".diamond.out"
            """
            diamond blastx -d ${params.nrdb} -q $best_fa -o $diamond_out -f 6 -p ${task.cpus}
            """
    }
} else if (params.aligner2 == "centrifuge"){

    process centrifuge_align_to_nt{
        tag "$name"

        cpus = params.centrifugeCPU

        publishDir "${params.results}/nt_alignment", mode: 'copy',
            saveAs: {filename ->  "./$filename"}

        input:
            set val(name), file(best_fa) from best_match

        output:
            file("*.centrifuge.out") into nt_aligned
            file("*_centrifuge_report.tsv") into nt_aligned_report

        script:
            centrifuge_out = name+".centrifuge.out"
            centrifuge_report = name+"_centrifuge_report.tsv"
            """
            centrifuge -x ${params.centrifugedb} -r $best_fa -p ${task.cpus} -f --report-file $centrifuge_report -S $centrifuge_out
            """
    }
/*
* STEP 10 - Assign LCA - Krona output
*/

    process CentrifugeToKrona {
        tag "${centrifuge_aligned[0].baseName}"


        publishDir "${params.results}/krona", mode: 'copy',
            saveAs: {filename ->  "./$filename"}

        input:
            file centrifuge_aligned from nt_aligned

        output:
            file("*_krona.html") into recentrifuge_result
            file("*_minhit*.out") into filtered_kraken_style_report

        script:
            """
            python $centrifuge2krona -index ${params.centrifugedb} -tax ${params.bastadb} $centrifuge_aligned
            """
    }
}


if (params.aligner2 == "diamond"){

    process lca_assignation {
        tag "$name"

        publishDir "${params.results}/taxonomy", mode: 'copy',
            saveAs: {filename ->
                if (filename.indexOf(".basta.out") > 0)  "./$filename"
            }

        input:
            set val(name), file(aligned_nr) from nr_aligned

        output:
            set val(name), file("*.basta.out") into lca_result

        script:
            basta_name = name+".basta.out"
            sorted_nr = name+"_diamond_nr.sorted"
            """
            sort -k3 -r -n $aligned_nr > $sorted_nr
            $basta sequence $sorted_nr $basta_name prot -d ${params.bastadb} -t ${params.bastamode} -m 1 -n ${params.bastanum} -i ${params.bastaid}
            """
    }


    process visual_results {
        tag "$name"

        publishDir "${params.results}/krona", mode: 'copy',
            saveAs: {filename ->  "./$filename"}

        input:
            set val(name), file(basta_res) from lca_result

        output:
            set val(name), file("*.krona.html") into krona_res
            set val(name), file("*_centriKraken_") into centri2kraken

        script:
            krona_out = name+".krona.html"
            """
            $basta2krona $basta_res $krona_out
            """
    }
}


/*
* STEP 11 - Generate MultiQC run summary
*/
if (params.adna == true){
    if (params.ctrl != "none"){
        process multiqc_ancient_dna_no_control {
            tag "$prefix"

            publishDir "${params.results}/MultiQC", mode: 'copy'

            input:
                file (fastqc:'fastqc_before_trimming/*') from fastqc_results.collect()
                file ('adapter_removal/*') from adapter_removal_results.collect()
                file("fastqc_after_trimming/*") from fastqc_results_after_trim.collect()
                file('aligned_to_blank/*') from ctrl_aln_metrics.collect()
                file('aligned_to_human/*') from human_aln_metrics.collect()
                file('aligned_to_organellomeDB/*') from organellome_aln_metrics.collect()

            output:
                file '*multiqc_report.html' into multiqc_report
                file '*_data' into multiqc_data

            script:
                prefix = fastqc[0].toString() - '_fastqc.html' - 'fastqc_before_trimming/'
                """
                multiqc -f -d fastqc_before_trimming adapter_removal fastqc_after_trimming aligned_to_human aligned_to_organellomeDB aligned_to_blank -c ${params.multiqc_conf}
                """
        }
    } else {
        process multiqc_ancient_dna_no_control {
            tag "$prefix"

            publishDir "${params.results}/MultiQC", mode: 'copy'

            input:
                file (fastqc:'fastqc_before_trimming/*') from fastqc_results.collect()
                file ('adapter_removal/*') from adapter_removal_results.collect()
                file("fastqc_after_trimming/*") from fastqc_results_after_trim.collect()
                file('aligned_to_human/*') from human_aln_metrics.collect()
                file('aligned_to_organellomeDB/*') from organellome_aln_metrics.collect()

            output:
                file '*multiqc_report.html' into multiqc_report
                file '*_data' into multiqc_data

            script:
                prefix = fastqc[0].toString() - '_fastqc.html' - 'fastqc_before_trimming/'
                """
                multiqc -f -d fastqc_before_trimming adapter_removal fastqc_after_trimming aligned_to_human aligned_to_organellomeDB -c ${params.multiqc_conf}
                """
        }
    }

} else {
    if (params.ctrl != "none"){
        process multiqc_modern_dna_with_control {
            tag "$prefix"

            publishDir "${params.results}/MultiQC", mode: 'copy'

            input:
                file (fastqc:'fastqc_before_trimming/*') from fastqc_results.collect()
                file ('adapter_removal/*') from adapter_removal_results.collect()
                file("fastqc_after_trimming/*") from fastqc_results_after_trim.collect()
                file('aligned_to_blank/*') from ctrl_aln_metrics.collect()
                file('aligned_to_human/*') from human_aln_metrics.collect()
                file('aligned_to_organellomeDB/*') from organellome_aln_metrics.collect()

            output:
                file '*multiqc_report.html' into multiqc_report
                file '*_data' into multiqc_data

            script:
                prefix = fastqc[0].toString() - '_fastqc.html' - 'fastqc_before_trimming/'
                """
                multiqc -f -d fastqc_before_trimming adapter_removal fastqc_after_trimming aligned_to_blank aligned_to_human aligned_to_organellomeDB -c ${params.multiqc_conf}
                """
        }
    } else {
        process multiqc_modern_dna_with_control {
            tag "$prefix"

            publishDir "${params.results}/MultiQC", mode: 'copy'

            input:
                file (fastqc:'fastqc_before_trimming/*') from fastqc_results.collect()
                file ('adapter_removal/*') from adapter_removal_results.collect()
                file("fastqc_after_trimming/*") from fastqc_results_after_trim.collect()
                file('aligned_to_human/*') from human_aln_metrics.collect()
                file('aligned_to_organellomeDB/*') from organellome_aln_metrics.collect()

            output:
                file '*multiqc_report.html' into multiqc_report
                file '*_data' into multiqc_data

            script:
                prefix = fastqc[0].toString() - '_fastqc.html' - 'fastqc_before_trimming/'
                """
                multiqc -f -d fastqc_before_trimming adapter_removal fastqc_after_trimming aligned_to_human aligned_to_organellomeDB -c ${params.multiqc_conf}
                """
        }
    }
}
