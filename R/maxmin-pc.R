
maxmin.pc.optimized = function(x, whitelist, blacklist, test,
  alpha, test.args, strict, debug = FALSE) {

  nodes = names(x)
  mb = list()

  for (node in nodes) {

    backtracking = unlist(sapply(mb, function(x){ node %in% x$nbr }))

    # 1. [Forward Phase (I)]
    mb[[node]] = maxmin.pc.forward.phase(node, data = x, nodes = nodes,
         alpha = alpha, test.args = test.args, whitelist = whitelist, blacklist = blacklist,
         backtracking = backtracking, test = test, optimized = TRUE,
         debug = debug)

    # 2. [Backward Phase (II)]
    mb[[node]] = neighbour(node, mb = mb, data = x, alpha = alpha,
         test.args = test.args, whitelist = whitelist, blacklist = blacklist,
         backtracking = backtracking, test = test, markov = FALSE, debug = debug)

  }#FOR

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#MAXMIN.PC.OPTIMIZED

maxmin.pc.cluster = function(x, cluster, whitelist, blacklist,
  test, alpha, test.args, strict, debug = FALSE) {

  nodes = names(x)

  # 1. [Forward Phase (I)]
  mb = parLapply(cluster, as.list(nodes), maxmin.pc.forward.phase, data = x,
         nodes = nodes, alpha = alpha, test.args = test.args, whitelist = whitelist,
         blacklist = blacklist, test = test, optimized = FALSE, debug = debug)
  names(mb) = nodes

  # 2. [Backward Phase (II)]
  mb = parLapply(cluster, as.list(nodes), neighbour, mb = mb, data = x,
         alpha = alpha, test.args = test.args, whitelist = whitelist, blacklist = blacklist,
         test = test, markov = FALSE, debug = debug)
  names(mb) = nodes

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#MAXMIN.PC.CLUSTER

maxmin.pc = function(x, whitelist, blacklist, test, alpha, test.args,
  strict, debug = FALSE) {

  nodes = names(x)

  # 1. [Forward Phase (I)]
  mb = lapply(as.list(nodes), maxmin.pc.forward.phase, data = x, nodes = nodes,
         alpha = alpha, test.args = test.args, whitelist = whitelist, blacklist = blacklist,
         test = test, optimized = FALSE, debug = debug)
  names(mb) = nodes

  # 2. [Backward Phase (II)]
  mb = lapply(as.list(nodes), neighbour, mb = mb, data = x, alpha = alpha,
         test.args = test.args, whitelist = whitelist, blacklist = blacklist, test = test,
         markov = FALSE, debug = debug)
  names(mb) = nodes

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#MAXMIN.PC

maxmin.pc.forward.phase = function(x, data, nodes, alpha, test.args, whitelist,
  blacklist, backtracking = NULL, test, optimized = TRUE, debug = FALSE) {

  nodes = nodes[nodes != x]
  known.good = known.bad = c()
  whitelisted = nodes[sapply(nodes,
          function(y) { is.whitelisted(whitelist, c(x, y), either = TRUE) })]
  blacklisted = nodes[sapply(nodes,
          function(y) { is.blacklisted(blacklist, c(x, y), both = TRUE) })]
  cpc = c()
  association = structure(numeric(length(nodes)), names = nodes)
  to.add = ""

  # growing phase
  if (debug) {

    cat("----------------------------------------------------------------\n")
    cat("* forward phase for node", x, ".\n")

  }#THEN

  # whitelisted nodes are included, and blacklisted nodes are excluded.
  cpc = whitelisted
  nodes = nodes[!(nodes %in% c(cpc, blacklisted))]

  # use backtracking for a further screening of the nodes to be checked.
  if (!is.null(backtracking) && optimized) {

    # nodes whose neighbourhood includes this node are included, because
    # X \in NBR(Y) <=> Y \in NBR(X); they can be removed in the backward
    # phase later on if they are false positives.
    known.good = names(backtracking[backtracking])
    cpc = unique(c(cpc, known.good))

    # and vice versa X not adiacent to Y <=> Y not adiacent to X
    known.bad = names(backtracking[!backtracking])

    # from empirical observations, MMPC has very few false negatives and
    # therefore it is fairly safe not to test known.bad nodes.
    nodes  = nodes[!(nodes %in% known.bad)] 

    if (debug) {

      cat("    * known good (backtracking): '", known.good, "'.\n")
      cat("    * known bad (backtracking): '", known.bad, "'.\n")
      cat("    * nodes still to be tested for inclusion: '",
        nodes[!(nodes %in% cpc)], "'.\n")

    }#THEN

  }#THEN

  # phase I (stepwise forward selection)
  repeat {

    # do not check nodes which have a p-value above the alpha threshold, as
    # it can only increase; also do not check 'known bad' ones.
    to.be.checked = setdiff(names(which(association < alpha)), c(cpc, known.bad))

    # get an association measure for each of the available nodes.
    association = sapply(to.be.checked, maxmin.pc.heuristic.optimized, y = x,
                    sx = cpc, data = data, test = test, alpha = alpha, test.args = test.args,
                    association = association, debug = debug)

    # stop if there are no candidates for inclusion.
    if (all(association > alpha) || length(nodes) == 0 || is.null(nodes)) break
    # get the one which maximizes the association measure.
    to.add = names(which.min(association))

    if (debug) {

      cat("  @", to.add, "accepted as a parent/children candidate ( p-value:",
        association[to.add], ").\n")
      cat("  > current candidates are '", c(cpc, to.add), "'.\n")

    }#THEN

    if (association[to.add] <= alpha) {

      cpc = c(cpc, to.add)
      nodes = nodes[nodes != to.add]

    }#THEN

  }#REPEAT

  return(cpc)

}#MAXMIN.PC.FORWARD.PHASE

maxmin.pc.heuristic.optimized = function(x, y, sx, data, test, alpha, test.args,
    association, debug = FALSE) {

  k = 0
  min.assoc = association[x]

  if (debug) {

    cat("  * checking node", x ,"for association.\n")
    cat("    > starting with association", min.assoc, ".\n")

  }#THEN

  # generate only the subsets of the current parent/children set
  # which include node added last; the rest are considered to be
  # already tested against.
  last = sx[length(sx)]
  sx = sx[-length(sx)]

  repeat {

    # create all the possible subsets of size k of the candidate
    # parent-children set.
    dsep.subsets = subsets(length(sx), k, sx)

    for (s in 1:nrow(dsep.subsets)) {

      a = conditional.test(x, y, c(dsep.subsets[s,], last), data = data,
            test = test, test.args = test.args, alpha = alpha)

      if (debug) {

        cat("    > trying conditioning subset '", c(dsep.subsets[s,], last), "'.\n")
        cat("    > node", x, "has p-value:", a, ".\n")

      }#THEN

      # minimum association means maximum p-value.
      min.assoc = max(min.assoc, a)

      # if the p-value is already this high, it's useless to do further
      # testing (as it min.assoc can only increase in value).
      if (min.assoc > alpha) break

    }#FOR

    # if the p-value is already this high, it's useless to do further
    # testing (as it min.assoc can only increase in value).
    if (min.assoc > alpha) break

    if (k < length(sx))
      k = k + 1
    else
      break

  }#REPEAT

  if (debug)
    cat("    > node", x, "has a minimum association of",
              min.assoc, ".\n")

  return(min.assoc)

}#MAXMIN.PC.HEURISTIC.OPTIMIZED

