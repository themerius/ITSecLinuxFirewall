.PHONY: pdf, clean

MAINTEX = main
CHAPTER = chapters/
TITLEPAGES = titlepages/
BUILDPATH = _build/
BUILDNAME = ITSEC-Laborbericht_M.Bumiller-S.Hodapp_2013

pdf:
	pdflatex $(MAINTEX).tex
	bibtex $(MAINTEX).aux
	pdflatex $(MAINTEX).tex
	pdflatex $(MAINTEX).tex
	mkdir -p $(BUILDPATH)
	mv $(MAINTEX).pdf $(BUILDPATH)$(BUILDNAME).pdf
	open $(BUILDPATH)$(BUILDNAME).pdf

clean:
	rm -f $(CHAPTER)*.aux
	rm -f $(TITLEPAGES)*.aux
	rm -f $(MAINTEX).aux $(MAINTEX).toc $(MAINTEX).log $(MAINTEX).out
	rm -f $(MAINTEX).lof $(MAINTEX).bbl $(MAINTEX).blg
