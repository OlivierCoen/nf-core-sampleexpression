process MERGE_COUNT_FILES {

    debug true

    conda "${moduleDir}/environment.yml"

    input:
    path csv_files

    output:
    path 'all_counts.csv', emit: csv
    tuple val("${task.process}"), val('python'),   eval('python3 --version'),                                         topic: versions
    tuple val("${task.process}"), val('pandas'),   eval('python3 -c "import pandas; print(pandas.__version__)"'),     topic: versions


    when:
    task.ext.when == null || task.ext.when

    script:
    """
    merge_count_files.py $csv_files --outfile all_counts.csv
    """

    stub:
    """
    touch all_counts.csv
    """

}
