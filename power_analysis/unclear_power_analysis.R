install.packages("pwr")
library(pROC)
data(aSAH)

roc1 <- roc(aSAH$outcome, aSAH$ndka)
roc2 <- roc(aSAH$outcome, aSAH$wfns)

## Sample size
# With DeLong variance (default)
power.roc.test(roc1, roc2, sig.level = 0.05, ncases = 400, ncontrol = 900)

library(pwr)
cohen.ES(test=c("f2"),    size=c("small"))
pwr.f2.test(u=30, v=300000, f2=0.02, sig.level=0.05, power=NULL)
?pwr.f2.test