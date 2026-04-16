FROM rocker/verse:4.4.1

WORKDIR /project

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    gdebi-core \
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    texlive-latex-base \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://quarto.org/download/latest/quarto-linux-amd64.deb -O /tmp/quarto.deb \
    && gdebi -n /tmp/quarto.deb \
    && rm -f /tmp/quarto.deb

COPY . /project

RUN Rscript scripts/setup_packages.R

CMD ["Rscript", "scripts/run_pipeline.R", "--profile", "full", "--clean-first"]
