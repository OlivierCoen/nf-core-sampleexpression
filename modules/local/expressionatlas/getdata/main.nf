process EXPRESSIONATLAS_GETDATA {

    // debug true

    // when there are network issues, we retry the download with a backoff
    // errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    // maxRetries 5

    // limiting threads to avoid crashing the G Profiler API server
    maxForks 4

    tag "$accession"

    conda "${moduleDir}/environment.yml"

    input:
    val(accession)

    output:
    tuple val(accession), path("*.design.csv"), path("*raw.csv"),                   optional: true,                 emit: raw
    tuple val(accession), path("*.design.csv"), path("*normalized.csv"),            optional: true,                 emit: normalized
    tuple val("${task.process}"), val('R'),               eval('Rscript -e "R.version.string"'),                    topic: versions
    tuple val("${task.process}"), val('ExpressionAtlas'), eval('Rscript -e "packageVersion(\'ExpressionAtlas\')"'), topic: versions


    when:
    task.ext.when == null || task.ext.when

    script:
    """
    get_expression_atlas_data.R --accession $accession
    """

    stub:
    """
    touch acc.raw.csv
    touch acc.design.csv
    """

}
