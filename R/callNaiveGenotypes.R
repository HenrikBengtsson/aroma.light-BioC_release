###########################################################################/**
# @RdocGeneric callNaiveGenotypes
# @alias callNaiveGenotypes.numeric
#
# @title "Calls genotypes in a normal sample"
#
# \description{
#   @get "title".
# }
#
# \usage{
# @usage callNaiveGenotypes,numeric
# }
#
# \arguments{
#  \item{y}{A @numeric @vector of length J containing allele B fractions
#    for a normal sample.}
#  \item{cn}{An optional @numeric @vector of length J specifying the true
#    total copy number in \eqn{\{0,1,2,NA\}} at each locus.  This can be
#    used to specify which loci are diploid and which are not, e.g.
#    autosomal and sex chromosome copy numbers.}
#  \item{...}{Additional arguments passed to @see "fitNaiveGenotypes".}
#  \item{modelFit}{A optional model fit as returned
#    by @see "fitNaiveGenotypes".}
#  \item{verbose}{A @logical or a @see "R.utils::Verbose" object.}
# }
#
# \value{
#   Returns a @numeric @vector of length J containing the genotype calls
#   in allele B fraction space, that is, in [0,1] where 1/2 corresponds
#   to a heterozygous call, and 0 and 1 corresponds to homozygous A
#   and B, respectively.
#   Non called genotypes have value @NA.
# }
#
# @examples "..\incl\callNaiveGenotypes.Rex"
#
# \section{Missing and non-finite values}{
#   A missing value always gives a missing (@NA) genotype call.
#   Negative infinity (-@Inf) always gives genotype call 0.
#   Positive infinity (+@Inf) always gives genotype call 1.
# }
#
# @author
#
# \seealso{
#   Internally @see "fitNaiveGenotypes" is used to identify the thresholds.
# }
#*/###########################################################################
setMethodS3("callNaiveGenotypes", "numeric", function(y, cn=rep(2L, times=length(y)), ..., modelFit=NULL, verbose=FALSE) {
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Validate arguments
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Argument 'y':
  J <- length(y);
  y <- as.double(y);

  # Argument 'cn':
  cn <- as.integer(cn);
  if (length(cn) == 1L) {
    cn <- rep(cn, times=J);
  } else if (length(cn) != J) {
    stop("The length of argument 'cn' does not match 'y': ",
                                            length(cn), " != ", J);
  }
  uniqueCNs <- sort(unique(cn));
  unknown <- which(!is.element(uniqueCNs, c(0,1,2,NA)));
  if (length(unknown) > 0L) {
    unknown <- paste(uniqueCNs[unknown], collapse=", ");
    stop("Argument 'cn' contains unknown CN levels: ", unknown);
  }

  # Argument 'modelFit':
  if (!is.null(modelFit)) {
    if (!inherits(modelFit, "NaiveGenotypeModelFit")) {
      throw("Argument 'modelFit' is not of class NaiveGenotypeModelFit: ", class(modelFit)[1]);
    }
  }

  # Argument 'verbose':
  verbose <- Arguments$getVerbose(verbose);
  if (verbose) {
    pushState(verbose);
    on.exit(popState(verbose));
  }


  verbose && enter(verbose, "Calling genotypes from allele B fractions (BAFs)");

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Fit naive genotype model?
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  if (is.null(modelFit)) {
    verbose && enter(verbose, "Fitting naive genotype model");
    modelFit <- fitNaiveGenotypes(y=y, cn=cn, ..., verbose=verbose);
    verbose && print(verbose, modelFit);
    verbose && exit(verbose);
  }


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Call genotypes
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  mu <- rep(NA_real_, times=J);

  # To please R CMD check
  type <- NULL; rm(list="type");

  # Fitted CNs
  cns <- sapply(modelFit, FUN=function(fit) fit$cn);
  for (kk in seq(along=uniqueCNs)) {
    cnKK <- uniqueCNs[kk];
    verbose && enter(verbose, sprintf("Copy number level #%d (C=%g) of %d", kk, cnKK, length(uniqueCNs)));

    # Special case
    if (cnKK == 0) {
      verbose && cat(verbose, "TCN=0 => BAF not defined. Skipping.");
      verbose && exit(verbose);
      next;
    }

    keep <- which(cn == cnKK);
    yKK <- y[keep];

    idx <- which(cnKK == cns);
    if (length(idx) != 1L) {
      msg <- sprintf("Cannot call genotypes for %d loci with true total copy number %d, because the naive genotype model was not fit for such copy numbers. Skipping.", length(yKK), cnKK);
      verbose && cat(verbose, msg);
      verbose && exit(verbose);
      next;
    }

    fitKK <- modelFit[[idx]];
    verbose && cat(verbose, "Model fit:");
    verbose && print(verbose, fitKK);

    tau <- fitKK$tau;
    if (is.null(tau)) {
      # Backward compatibility
      fitValleys <- fitKK$fitValleys;
      verbose && cat(verbose, "Local minimas (\"valleys\") in BAF:");
      verbose && print(verbose, fitValleys);
      tau <- fitValleys$x;
      # Not needed anymore
      fitValleys <- NULL;
    }
    verbose && printf(verbose, "Genotype threshholds [%d]: %s\n", length(tau), hpaste(tau));


    # Call genotypes
    muKK <- rep(NA_real_, times=length(yKK));
    if (cnKK == 1) {
      verbose && cat(verbose, "TCN=1 => BAF in {0,1}.");
      a <- tau[1];
      verbose && printf(verbose, "Call regions: A = (-Inf,%.3f], B = (%.3f,+Inf)\n", a, a);
      muKK[yKK <= a] <- 0;
      muKK[a < yKK] <- 1;
    } else if (cnKK == 2) {
      verbose && cat(verbose, "TCN=2 => BAF in {0,1/2,1}.");
      a <- tau[1];
      b <- tau[2];
      verbose && printf(verbose, "Call regions: AA = (-Inf,%.3f], AB = (%.3f,%.3f], BB = (%.3f,+Inf)\n", a, a, b, b);
      muKK[yKK <= a] <- 0;
      muKK[a < yKK & yKK <= b] <- 1/2;
      muKK[b < yKK] <- 1;
    } else {
      verbose && printf(verbose, "TCN=%d => Skipping.\n", cnKK);
    }
    mu[keep] <- muKK;

    verbose && exit(verbose);
  } # for (kk ...)

  # Sanity check
  stopifnot(length(mu) == J);


  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # Return genotype calls (and parameter estimates)
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  attr(mu, "modelFit") <- modelFit;

  verbose && exit(verbose);

  mu;
}) # callNaiveGenotypes()


###########################################################################
# HISTORY:
# 2012-04-16
# o CLEANUP: Dropped argument 'flavor' of callNaiveGenotypes(); it is
#   now passed to fitNaiveGenotypes() via '...'.
# o GENERALIZATION: Now callNaiveGenotypes() no longer relies on 'modelFit'
#   to hold a 'fitValleys' element, but rather a 'tau' element.
# 2010-10-14
# o TYPO FIX: Used name 'fitPeaks' instead of 'fitValleys'.
# 2010-10-07
# o Now callNaiveGenotypes() utilizes fitNaiveGenotypes().
# o Added more detailed verbose to callNaiveGenotypes().
# 2010-07-23
# o Now callNaiveGenotypes() returns the model estimates as attribute
#   'modelFit'.
# 2010-04-04
# o Updated code such that R.utils::Verbose is optional.
# o Corrected an Rdoc tag typo.
# 2009-11-03
# o Added an example() to the Rd help of callNaiveGenotypes().
# 2009-07-08
# o BUG FIX: Was never tested. Now tested via example(normalizeTumorBoost).
# 2009-07-06
# o Created from aroma.cn test script.
###########################################################################
