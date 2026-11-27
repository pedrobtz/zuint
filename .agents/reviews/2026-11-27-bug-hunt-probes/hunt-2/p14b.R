b <- deparse(`[<-.data.frame`)
i <- grep("pad|xtfrm|length\\(x\\[\\[|n > nrows|nrows <|xpdrows", b)
print(b[sort(unique(unlist(lapply(i, function(k) max(1, k - 2):min(length(b), k + 4)))))])
print(base:::xpdrows.data.frame)
