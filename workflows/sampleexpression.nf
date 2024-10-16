/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { EXPRESSIONATLAS_GETACCESSIONS          } from '../modules/local/expressionatlas/getaccessions/main'
include { EXPRESSIONATLAS_GETDATA                } from '../modules/local/expressionatlas/getdata/main'
include { DESEQ2_NORMALIZE                       } from '../modules/local/deseq2/normalize/main'
include { EDGER_NORMALIZE                        } from '../modules/local/edger/normalize/main'
include { IDMAPPING                              } from '../modules/local/idmapping/main'
include { MERGE_COUNT_FILES                      } from '../modules/local/merge_count_files/main'
include { MERGE_DESIGNS                          } from '../modules/local/merge_designs/main'
include { paramsSummaryMap                       } from 'plugin/nf-validation'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SAMPLEEXPRESSION {

    //
    // Checking input parameters
    //

    if (!params.species && params.expression_atlas_keywords) {
        error('You must provide a species name if you specify expression atlas keywords')
    }

    if (!params.count_dataset && !params.species) {
        error('You must provide at least either count datasets or a species name')
    }

    ch_versions = Channel.empty()

    if (params.species) {

        ch_species = Channel.value(params.species)
        // since we combine both channles, we need to ensure that the keywords channel contains at least one element
        if (params.expression_atlas_keywords == null || params.expression_atlas_keywords == []) {
            params.expression_atlas_keywords = [null]
        }
        ch_keywords = Channel.fromList(params.expression_atlas_keywords)

        //
        // MODULE: Expression Atlas - Get accessions
        //

        ch_species.combine(ch_keywords) | EXPRESSIONATLAS_GETACCESSIONS

        //
        // MODULE: Expression Atlas - Get data
        //

        ch_accessions = EXPRESSIONATLAS_GETACCESSIONS
                            .out
                            .csv
                            .splitCsv()
                            .map{ row -> "${row[0]}"}

        EXPRESSIONATLAS_GETDATA(ch_accessions)

        //
        // MODULE: Merge the design CSV files into one single file
        //

        MERGE_DESIGNS(EXPRESSIONATLAS_GETDATA.out.design.collect())
        ch_design = MERGE_DESIGNS.out.csv

        // separating raw and normalized counts
        EXPRESSIONATLAS_GETDATA
            .out
            .csv
            .branch {
                raw: { file -> file.name.endsWith('raw.csv') }
                normalized: { file -> file.name.endsWith('normalized.csv') }
            }
            .set{ ch_datasets }

        //
        // MODULE: Normalization of raw count datasets
        //

        if (params.normalization_method == 'deseq2') {
            DESEQ2_NORMALIZE(
                ch_datasets.raw,
                ch_design
            )
            ch_norm = DESEQ2_NORMALIZE.out.csv

        } else {
            EDGER_NORMALIZE(
                ch_datasets.raw,
                ch_design
            )
            ch_norm = EDGER_NORMALIZE.out.csv
        }

        // putting all normalized count datasets together
        ch_normalized_datasets = ch_datasets.normalized.concat(ch_norm)

        //
        // MODULE: Id mapping
        //

        ch_normalized_datasets.combine(ch_species) | IDMAPPING

        //
        // MODULE: Run Merge count files
        //

        MERGE_COUNT_FILES(IDMAPPING.out.csv.collect())

        MERGE_COUNT_FILES.out.csv.view()

    }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
