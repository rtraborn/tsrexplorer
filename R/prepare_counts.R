
#' Format Counts
#'
#' Format counts for TSSs, TSRs, and/or features.
#'
#' @param experiment tsrexplorer object
#' @param data_type 'tss', 'tsr', or 'features'
#'
#' @rdname format_counts-function
#' @export

format_counts <- function(experiment, data_type = c("tss", "tsr", "features")) {

	## Grab appropriate samples and generate raw count matrices.
	if (data_type == "tss") {

		## Grab selected_samples.
		if (length(samples) == 1 & samples == "all") samples <- names(tss_experiment(experiment))
		select_samples <- tss_experiment(experiment)[samples]

		## Create raw count matrix.
		raw_matrix <- select_samples %>%
			map(as.data.table) %>%
			bind_rows(.id = "sample")		
		raw_matrix <- dcast(raw_matrix, seqnames + start + end + strand ~ sample, fill = 0)

	} else if (data_type == "tsr") {

		## Grab selected samples.
		if (length(samples) == 1 & samples == "all") samples <- names(tsr_experiment(experiment))
		select_samples <- tsr_experiment(experiment)[samples]

		## Merge overlapping TSRs to get consensus.
		tsr_consensus <- select_samples %>%
			purrr::reduce(c) %>%
			GenomicRanges::reduce(ignore.strand = FALSE)

		## Create raw count matrix.
		raw_matrix <- select_samples %>%
			map(
				~ findOverlapPairs(query = tsr_consensus, subject = .) %>%
				as.data.table
			) %>%
			bind_rows(.id = "sample")
		raw_matrix <- setnames(
			raw_matrix,
			old = c(
				"first.seqnames", "first.start", "first.end",
				"first.strand", "second.X.score"
			),
			new = c("seqnames", "start", "end", "strand", "score")
		)
		raw_matrix <- raw_matrix[,
			.(score = sum(score)),
			by = .(sample, seqnames, start, end, strand)
		]
		raw_matrix <- dcast(raw_matrix, seqnames + start + end + strand ~ sample, fill = 0)
	
	}

	## Create RangedSummarizedExperiment for regular counts.
	if (data_type %in% c("tss", "tsr")) {
		raw_counts <- select_samples %>%
			imap(function(gr, sample_name) {
				count_data <- gr %>%
					score(.) %>%
					as.matrix %>%
					set_colnames(sample_name)

				row_data <- gr
				score(row_data) <- NULL
				col_data <- DataFrame(sample = sample_name)

				raw_exp <- SummarizedExperiment(
					assays = list(raw = count_data),
					rowRanges = row_data,
					colData = col_data
				)
				return(raw_exp)
			})
	}

	## Create RangedSummarizedExperiment for count matrices.
	if (data_type %in% c("tss", "tsr")) {
		count_matrix <- as.matrix(raw_matrix[,-1:-4])
		row_data <- makeGRangesFromDataFrame(raw_matrix)
	}
	
	col_data <- DataFrame("sample" = colnames(count_matrix), row.names = colnames(count_matrix))
	
	matrix_counts <- SummarizedExperiment(
		assays = list(counts = count_matrix),
		rowRanges = row_data,
		colData = col_data
	)

	## Place counts in proper object slot.
	if (data_type == "tss") {
		experiment@counts$TSSs <- list(
			"raw" = raw_counts,
			"matrix" = matrix_counts
		)
	} else if (data_type == "tsr") {
		experiment@counts$TSRs <- list(
			"raw" = raw_counts,
			"matrix" = matrix_counts
		)
	}

	return(experiment)
}

#' CPM Normalize Counts
#'
#' CPM normalize the TSS, TSR, and/or feature counts.
#'
#' @param experiment tsrexplorer object
#' @param data_type 'tss', 'tsr', or 'features'
#'
#' @rdname cpm_normalize-function
#' @export

cpm_normalize <- function(experiment, data_type = c("tss", "tsr", "features")) {
	
	## Grab appropriate samples.
	if (data_type == "tss") {
		select_samples <- experiment@counts$TSSs$raw
	} else if (data_type == "tsr") {
		select_samples <- experiment@counts$TSRs$raw
	}

	## CPM normalize counts.
	cpm_counts <- select_samples %>%
		map(function(x) {
			cpm_matrix <- cpm(assay(x, "raw"))
			assay(x, "cpm") <- cpm_matrix
			return(x)
		})

	## Add data back to object.
	if (data_type == "tss") {
		experiment@counts$TSSs$raw <- cpm_counts
	} else if (data_type == "tsr") {
		experiment@counts$TSRs$raw <- cpm_counts
	}

	return(experiment)
}