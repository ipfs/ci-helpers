ORB_NAME := ipfs/ci-go

help:
	@echo "ipfs/ci-go orb"
	@echo "Commands:"
	@echo "  make validate - validate the orb"
	@echo ""
	@echo "  make publish-patch - publish a new patch version"
	@echo "  make publish-minor - publish a new minor version"
	@echo "  make publish-major - publish a new major version"
.PHONY: help

validate:
	circleci config pack . | circleci config validate -
.PHONY: validate

publish-%:
	circleci config pack . | circleci orb publish increment - $(ORB_NAME) $(patsubst publish-%,%,$@)
PHONY: publish-%
