library(pwr)

?pwr.f2.test

u <- 11 # 10 numerator degrees of freedom

cohen.ES(test=c("f2"),    size=c("small"))
f2 <- 0.02 # R^2 = 0.02 => f2 = 0.02

# significance = 0.05

power <- 0.8 # power = 0.8

res <- pwr.f2.test(u = u, f2 = f2, power = power)
v <- res$v

# n = v + u + 1
n <- v + u + 1
n # 849.9684

install.packages("bibtex")

bibtex::write.bib("pwr", file = "pwr.bib")
