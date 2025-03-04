#' Plot spatial verification scores
#'
#' \code{plot_spatial_verif} is used to plot verification scores computed by
#' functions from the harpSpatial package.
#'
#' @param verif_data Output from \link[harpSPatial]{spatial_verify}
#' @param score The score to plot. Currently only SAL, FSS are available.
#'   More to come.
#' @param filter_by Filter the data before plotting. Must be wrapped inside the
#'   \link[dplyr]{vars} function. This can be useful for making a single plot
#'   where there are many groups. For example, if the data contains various models
#'   the data can be filtered with
#'   e.g. \code{filter_by = vars(det_model == "be13", fctime == 0)}.
#'
#' @export

plot_spatial_verif <- function(
  verif_data,
  score,
  filter_by = NULL,
  ...) {

  score_quo   <- rlang::enquo(score)
  score_name <- rlang::quo_name(score_quo)

 
  # the column(s) to filter data for before plotting
  filter_by_err  <- paste("filter_by must be wrapped in vars and unquoted,\n",
    "e.g. filter_by = vars(leadtime == 12, threshold == 280).")
  filter_by_null <- try(is.null(filter_by), silent = TRUE)
  filter_vars    <- ""
  if (inherits(filter_by_null, "try-error")) {
    stop(filter_by_err, call. = FALSE)
  } else {
    if (filter_by_null) {
      filtering <- FALSE
    } else {
      if (inherits(filter_by, "quosures")) {
        filtering <- TRUE
        filter_vars <- names(purrr::map_chr(rlang::eval_tidy(filter_by), rlang::quo_name))
      } else {
        stop(filter_by_err, call. = FALSE)
      }
    }
  }

  # select the right data set if verif_data is a list of tables

  if (!is.data.frame(verif_data) && is.list(verif_data)) {
    plot_data <- switch(tolower(score_name),
                        "sal" = verif_data$basic,
                        "fss" = verif_data$fuzzy,
                        stop("unsupported score ", score_name)
                        )
  } else {
    plot_data <- verif_data
  }

  # apply filtering
  if (filtering) {
    plot_data <- dplyr::filter(plot_data, !!! filter_by)
  }

  # at this point: only 1 model and 1 prm should be in the data
  # in fact, the function should also allow input data without these columns!
  if (is.element("model", names(plot_data))) {
    myModel <- unique(plot_data$model)
    if (length(myModel) > 1) stop("You are mixing several models in a single SAL plot.")
  } else {
    myModel <- NULL
  }

  if (is.element("prm", names(plot_data))) {
    myParam <- unique(plot_data$prm)
    if (length(myParam) > 1) stop("You are mixing several parameters in a single SAL plot.")
  } else {
    myParam <- NULL
  }

  # for the plot title, 
  # now create the actual plot by calling helper functions
  switch(tolower(score_name),
    "sal" = {
       gg <- plot_sal(plot_data)
    },
    "fss" = {
       gg <- plot_fuzzy(plot_data, "fss")
    },
    stop("unknown score ", score_name)
    )

  # add a title
  # we assume fcdate is a column of YYYYMMDD strings (or integers), not POSIX dates
  if (is.element("fcdate", names(plot_data))) {

    bdate <- min(plot_data$fcdate, na.rm=TRUE)
    bdate <- as.Date(as.character(bdate),"%Y%m%d")
    edate <- max(plot_data$fcdate, na.rm=TRUE)
    edate <- as.Date(as.character(edate),"%Y%m%d")
    fcvalues <- c(unique(plot_data$fctime))

} else {

    bdate <- NULL
    edate <- NULL
    fcfirst <- NULL
    fclast <- NULL

  }
  
  plot.title <- sprintf("%s\n",paste(toupper(score_name),"Diagram",sep = " "), bdate, edate)
  gg <- gg + ggplot2::labs(title=plot.title, 
                           subtitle = paste(" Model: ", myModel,"\n","Period: ","from", bdate,"to", edate, "\n" ), 
                           caption = paste("Parameter: ", myParam)) +
             ggplot2::theme(plot.title = element_text(hjust = .5))
   

  # finished
  gg
}

### support functions for specific scores

plot_sal <- function(plot_data) {
  if (is.null(plot_data)) stop("No data found.")
  # check that you have columns S, A, L
  if (any(!is.element(c("S", "A", "L"), names(plot_data)))) stop("plot_data must have columns named S, A and L !")
  medianS <- sprintf("S median = %.04f ", median(plot_data$S, na.rm=TRUE))
  medianA <- sprintf("A median = %.04f ", median(plot_data$A, na.rm=TRUE))
  medianL <- sprintf("L median = %.04f ", median(plot_data$L, na.rm=TRUE))

  meanS <- sprintf("S mean = %.04f ", mean(plot_data$S, na.rm=TRUE))
  meanA <- sprintf("A mean = %.04f ", mean(plot_data$A, na.rm=TRUE))
  meanL <- sprintf("L mean = %.04f ", mean(plot_data$L, na.rm=TRUE))

  tab <- matrix(c(meanS,meanA,meanL,medianS,medianA,medianL),ncol=1)

  totalHITS  <- sum(plot_data$hits, na.rm=TRUE)
  totalMISS  <- sum(plot_data$miss, na.rm=TRUE)
  totalTOTAL <- sum(plot_data$total, na.rm=TRUE)
  totalFA    <- sum(plot_data$fa, na.rm=TRUE)
  totalCN    <- sum(plot_data$cn, na.rm=TRUE)

  totalAC    <- (totalHITS + totalCN)/totalTOTAL
  totalSR    <- totalHITS/(totalHITS + totalFA)
  totalBSF   <- (totalHITS + totalFA)/(totalHITS + totalMISS)
  totalPOD   <- totalHITS/(totalHITS + totalFA)
  totalFAR   <- totalFA/(totalHITS + totalFA)
  totalPOFD  <- totalFA/(totalCN + totalFA)

  mytable <- data.frame(ac=totalAC,sr=totalSR,bsf=totalBSF,pod=totalPOD,far=totalFAR,pofd=totalPOFD)%>%
                mutate(across(where(is.numeric), ~ round(., digits = 2)))
  colnames(tab) <- 'score'
  rownames(tab) <- c('meanS','meanA','meanL','medianS','medianA','medianL')
  tab <- as.table(tab)

  tt1 <- ttheme_default()
  tt2 <- ttheme_minimal()
  
  tfsize <- 3.5
  tfam <- "mono"
  
  gg <- ggplot2::ggplot(plot_data, aes(x = S, y = A, colour = plot_data$L))
  gg <- gg + ggplot2::geom_point(size=5) +
             ggplot2::xlim(-2, 2) + ggplot2::ylim(-2, 2) + 
             ggplot2::labs(y = "A", x = "S", colour="L") +
             ggplot2::scale_colour_gradient2(low = "darkblue", mid = "yellow", high = "red") +

             ggplot2::annotate(geom = "rect", xmin = quantile(plot_data$S, probs=.25), xmax = quantile(plot_data$S, probs=.75),
                                              ymin = quantile(plot_data$A,probs=.25), ymax = quantile(plot_data$A,probs=.75),
                                              fill = "gray42", color = "gray70", alpha = 0.1) +

             ggplot2::geom_text(aes(-1.2,2,label = medianS, family=tfam), size=tfsize*1.5, colour="black") + 
             ggplot2::geom_text(aes(-1.2,1.8,label = medianA, family=tfam), size=tfsize*1.5, colour="black") + 
             ggplot2::geom_text(aes(-1.215,1.6,label = medianL, family=tfam), size=tfsize*1.5, colour="black") + 
             ggplot2::geom_text(aes(1.211,-1.6,label = meanS, family=tfam), size=tfsize*1.5, colour="black") +  
             ggplot2::geom_text(aes(1.2,-1.8,label = meanA, family=tfam), size=tfsize*1.5, colour="black") +  
             ggplot2::geom_text(aes(1.2,-2,label = meanL, family=tfam), size=tfsize*1.5, colour="black")+ 
             ggplot2::geom_hline(yintercept = median(plot_data$A, na.rm=TRUE), linetype = "dashed",color = "#8c8c8c") +
             ggplot2::geom_vline(xintercept = median(plot_data$S, na.rm=TRUE), linetype = "dashed", color = "#8c8c8c") +
             ggplot2::annotation_custom(tableGrob(mytable, rows=NULL,theme=tt2), xmin=-2., xmax=-0.5, ymin=-2.5, ymax=-0.99)
  gg
}

plot_fuzzy <- function(plot_data, score_name="fss") {
  if (is.null(plot_data)) stop("No data found.")
  if (any(!is.element(c("threshold", "scale", score_name), names(plot_data)))) {
    stop("plot_data must have columns named threshold, scale and", score_name, " !")
  }

  ### calculate mean of every threshold/scale pair 
  data_matrix <- plot_data %>% dplyr::group_by(threshold, scale) %>% dplyr::summarize_at(score_name, mean, na.rm=TRUE)

  gg <- ggplot2::ggplot(data_matrix, aes(x=as.factor(threshold),y=as.factor(scale), 
                             fill = get(score_name), 
                             label = sprintf("%1.2f", get(score_name)))) + 
    # scale_y_discrete(expand=c(0,0)) +
    ggplot2::geom_tile() + ggplot2::geom_text(colour = "black", size = 4) +
    ggplot2::scale_fill_gradient2(low = "red", mid="yellow", high = "darkgreen", 
                         limits=c(0, 1), midpoint=0.5, name = score_name) +
    # theme(axis.title.x = element_blank()) +   # Remove x-axis label
    ggplot2::theme(axis.title.x = element_text(size=14), axis.text.x = element_text(size=14),
          axis.title.y = element_text(size=14), axis.text.y = element_text(size=14)) +
    ggplot2::ylab("spatial scale")  + ggplot2::xlab("threshold") +
    ggplot2::theme_bw(base_size=14)

  # guides(fill = guide_legend(title.theme = element_text(size=15, angle=0),
  #                            label.theme = element_text(size=15, angle=0))) # ,
  #   keywidth = 2, keyheight = 3))
  # scale_x_discrete(expand=c(0,0))
  gg

}


