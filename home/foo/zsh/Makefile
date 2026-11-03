SRCS := $(wildcard *.zsh)
SRCS := $(filter-out bindkeys.zsh, $(SRCS))
fmt:
	shfmt -l -w $(SRCS)