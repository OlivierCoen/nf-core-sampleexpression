/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { EXPRESSIONATLAS_GETACCESSIONS          } from '../modules/local/expressionatlas/getaccessions/main'
include { EXPRESSIONATLAS_GETDATA                } from '../modules/local/expressionatlas/getdata/main'
include { DESEQ2_NORMALIZE                       } from '../modules/local/deseq2/normalize/main'
include { EDGER_NORMALIZE                        } from '../modules/local/edger/normalize/main'
include { IDMAPPING                              } from '../modules/local/gprofiler/idmapping/main'
include { MERGE_COUNT_FILES                      } from '../modules/local/merge_count_files/main'
include { MERGE_DESIGNS                          } from '../modules/local/merge_designs/main'
include { VARIATION_COEFFICIENT                  } from '../modules/local/variation_coefficient/main'

include { paramsSummaryMap                       } from 'plugin/nf-validation'
include { samplesheetToList                      } from 'plugin/nf-schema'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow STABLEEXPRESSION {

    //
    // Checking input parameters
    //

    if (params.expression_atlas_keywords && !params.fetch_from_expression_atlas) {
        error('You must provide a species name if you specify expression atlas keywords')
    }

    if (!params.input && !params.fetch_from_expression_atlas) {
        error('You must provide at least either input datasets or a species name')
    }

    def species = params.species.split(' ').join('_')
    ch_species = Channel.value(species)

    ch_normalized = Channel.empty()
    ch_raw = Channel.empty()

    if (params.input) {

        log.info "Parsing input data"

        Channel.fromList(samplesheetToList(params.input, "${projectDir}/assets/schema_input.json"))
            .map {
                item ->
                    def (count_file, design_file, normalized) = item
                    meta = [accession: count_file.name, design: design_file]
                    [meta, count_file, normalized]
            }
            .branch {
                item ->
                    normalized: item[2] == true
                    raw: item[2] == false
            }
            .set { ch_input }

        // removes the third element ("normalized" column) and adds to the corresponding channel
        ch_normalized = ch_normalized.concat(
            ch_input.normalized.map{ it -> it.take(2) }
        )
        ch_raw = ch_raw.concat(
            ch_input.raw.map{ it -> it.take(2) }
        )

    }

    if (params.fetch_from_expression_atlas) {

        ch_keywords = Channel.value(params.expression_atlas_keywords)

        log.info "Fetching count dataset from Expression Atlas"

        //
        // MODULE: Expression Atlas - Get accessions
        //

        EXPRESSIONATLAS_GETACCESSIONS(ch_species, ch_keywords)

        //
        // MODULE: Expression Atlas - Get data
        //

        ch_accessions = EXPRESSIONATLAS_GETACCESSIONS.out.txt.splitText()

        EXPRESSIONATLAS_GETDATA(ch_accessions)

        ch_normalized = ch_normalized.concat(
            EXPRESSIONATLAS_GETDATA.out.normalized.map {
                tuple ->
                    def (accession, design_file, count_file) = tuple
                    meta = [accession: accession, design: design_file]
                    [meta, count_file]
            }
        )

        ch_raw = ch_raw.concat(
            EXPRESSIONATLAS_GETDATA.out.raw.map {
                tuple ->
                    def (accession, design_file, count_file) = tuple
                    meta = [accession: accession, design: design_file]
                    [meta, count_file]
                }
        )

    }

    //
    // MODULE: Normalization of raw count datasets (including RNA-seq datasets)
    //

    if (params.normalization_method == 'deseq2') {
        DESEQ2_NORMALIZE(ch_raw)
        ch_raw_normalized = DESEQ2_NORMALIZE.out.csv

    } else {
        EDGER_NORMALIZE(ch_raw)
        ch_raw_normalized = EDGER_NORMALIZE.out.csv
    }

    // putting all normalized count datasets together
    ch_normalized.concat(ch_raw_normalized).set{ ch_all_normalized }

    //
    // MODULE: Id mapping
    //

    IDMAPPING(ch_all_normalized.combine(ch_species))

    //
    // MODULE: Run Merge count files
    //

    MERGE_COUNT_FILES(IDMAPPING.out.csv.collect())

    //
    // MODULE: Compute variation coefficient for each gene
    //

    VARIATION_COEFFICIENT(MERGE_COUNT_FILES.out.csv)
    ch_var_coeff = VARIATION_COEFFICIENT.out.csv



    emit:
    ch_var_coeff
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
