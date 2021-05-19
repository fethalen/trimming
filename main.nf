#!/usr/bin/env nextflow

nextflow.enable.dsl=2

def helpMessage() {
  log.info"""
  Description:
    Trimming and quality control on single- or paired-ended reads.

  Pipeline summary:
    1. Quality control using FastQC
    2. Adapter and quality trimming using Trim Galore!

  Usage:
    (1) Single-end reads:
      nextflow run main.nf --single-end --reads '*\\.fastq\\.gz'
    (2) Paired-end reads:
      nextflow run main.nf --reads '*_R{1,2}\\.fastq\\.gz'

  Mandatory arguments:
    --reads             path to one or more sets of paired-ended reads (valid
                        file types: .fastq.gz', '.fq.gz', '.fastq', or '.fq')

  Input/output options:
    --single_end        when specified, input reads are single-end reads
                        (default: $params.single_end)
    --output            path to a directory which the results are written to
                        (default: $params.output)

  Quality control:
    --qc_adapters       path to adapters files, if any (default: $params.qc_adapters)

  Trimming (Trim Galore!):
    --trim_min_length   discards reads shorter than this (default: $params.trim_min_length)
    --trim_quality      Phred score threshold for quality trimming (default: $params.trim_quality)
    --trim_adapter      adapter sequence to be trimmed (default: auto-detect)
    --trim_phred64      use Phred+64 (i.e., Illumina 1.5) encoding for quality scores
                        (default: Phred+33; Sanger/Illumina 1.8)
    --trim_forward_leading
                        cut off bases at the start of the forward reads or all
                        reads if single-end reads (default: $params.trim_forward_leading)
    --trim_forward_trailing
                        cut off bases at the end of the forward reads or all
                        reads if single-end reads (default: $params.trim_forward_trailing)
    --trim_reverse_leading
                        cut off bases at the start of the forward reads or all
                        reads if single-end reads (default: $params.trim_reverse_leading)
    --trim_reverse_trailing
                        cut off bases at the end of the forward reads or all
                        reads if single-end reads (default: $params.trim_reverse_trailing)
    --trim_forward_cutoff POSITION
                        remove all bases past this position
                        cut off bases at the end of the forward reads or all
                        reads if single-end reads (default: $params.trim_forward_trailing)
    --trim_leading_cutoff
                        INSTEAD of trimming, remove all bases past this position
                        (default: '$params.trim_leading_cutoff')
    --trim_trailing_cutoff
                        INSTEAD of trimming, remove all bases such that there
                        are this many bases from the 3' end (default: '$params.trim_trailing_cutoff')

  Flow control:
    --skip_qc           skip raw read quality assessment (default: $params.skip_qc)
    --skip_trimming     skip trimming step (default: $params.skip_trimming)

  Miscellaneous:
    --help              display this help message and exit
    --version           display this pipeline's version number and exit
  """.stripIndent()
}

def versionNumber() {
  log.info"Genome assembly pipeline ~ version $workflow.manifest.version"
}

// Display the version number upon request
if ( params.version ) exit 0, versionNumber()

// Display a help message upon request
if ( params.help ) exit 0, helpMessage()

// Input validation
if ( params.reads == null ) {
  exit 1, "Missing mandatory argument '--reads'\n" +
          "Launch this workflow with '--help' for more info"
}

rawReads = Channel
  .fromFilePairs( params.reads, size: params.single_end ? 1 : 2, type: 'file' )
  .filter { it =~/.*\.fastq\.gz|.*\.fq\.gz|.*\.fastq|.*\.fq/ }
  .ifEmpty { exit 1,
             "No FASTQ files found with pattern '${params.reads}'\n" +
             "Escape dots ('.') with a backslash character ('\\')\n" +
             "Try enclosing the path in single-quotes (')\n" +
             "Valid file types: '.fastq.gz', '.fq.gz', '.fastq', or '.fq'\n" +
             "For single-end reads, specify '--single-end'" }

/*
 * Read quality control using FastQC
 */
process rawReadsQuality {
  conda "$baseDir/environment.yml"
  publishDir "${params.output}/quality_control_pre-trimming", mode: 'copy'

  input:
  tuple val(name), path(reads)

  output:
  path "*_fastqc.{zip,html}"
  path "fastqc_command.txt"

  when:
  ! params.skip_qc

  script:
  """
  fastqc_command="fastqc --threads ${task.cpus} --quiet $reads"
  \$fastqc_command
  echo "\$fastqc_command" > 'fastqc_command.txt'
  rename 's/_fastqc\\.zip\$/_pre-trimming_fastqc.zip/' *_fastqc.zip
  rename 's/_fastqc\\.html\$/_pre-trimming_fastqc.html/' *_fastqc.html
  """
}

if ( params.skip_trimming ) {
  trimmedReads = rawReads
}

/*
 * Adapter removal and read trimming using Trim Galore!
 */
process trimming {
  conda "$baseDir/environment.yml"
  publishDir "${params.output}/trimmed_reads", mode: 'copy'

  input:
  tuple val(name), path(reads)

  output:
  tuple val(name), path("*.fq.gz")
  path "*.txt"
  path "*.{zip,html}"

  when:
  ! params.skip_trimming

  script:
  flagsTrimming = "--fastqc --gzip --quality $params.trim_quality \
--length $params.trim_min_length --cores $task.cpus"
  if ( params.trim_phred64 )
    flagsTrimming += " --phred64"
  if ( params.trim_forward_leading )
    flagsTrimming += " --clip_R1 $params.trim_forward_leading"
  if ( params.trim_forward_trailing )
    flagsTrimming += " --three_prime_clip_R1 $params.trim_forward_trailing"
  if ( params.trim_reverse_leading )
    flagsTrimming += " --clip_R2 $params.trim_reverse_leading"
  if ( params.trim_reverse_trailing )
    flagsTrimming += " --three_prime_clip_R2 $params.trim_reverse_trailing"
  if ( ! params.single_end )
    flagsTrimming += " --paired --retain_unpaired"
  commandTrimming = "trim_galore $flagsTrimming $reads"

  """
  $commandTrimming
  echo "$commandTrimming" > 'trim_galore_command.txt'
  """
}

workflow {
  rawReadsQuality(rawReads)
  trimming(rawReads)
}

workflow.onComplete {
  // Display complete message
  log.info "Completed at: " + workflow.complete
  log.info "Duration    : " + workflow.duration
  log.info "Success     : " + workflow.success
  log.info "Exit status : " + workflow.exitStatus
}

workflow.onError {
  // Display error message
  log.info "Workflow execution stopped with the following message:"
  log.info "  " + workflow.errorMessage
}
