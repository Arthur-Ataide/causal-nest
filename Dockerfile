FROM python:3.9-buster AS base

ENV DEBIAN_FRONTEND=noninteractive \
    CRAN_MIRROR=https://cloud.r-project.org \
    POETRY_HOME="/opt/poetry" \
    PATH="/opt/poetry/bin:$PATH"

# Configurar repositórios para Debian oldstable
RUN echo "deb http://archive.debian.org/debian/ buster main" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security/ buster/updates main" >> /etc/apt/sources.list && \
    echo "Acquire::Check-Valid-Until \"false\";" > /etc/apt/apt.conf.d/10no-check-valid-until

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    dirmngr \
    apt-transport-https \
    libseccomp-dev \
    seccomp \
    libssl-dev \
    libgmp3-dev \
    git \
    build-essential \
    libv8-dev \
    libcurl4-openssl-dev \
    libgsl-dev \
    libxml2-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    graphviz \
    tzdata \
    dialog \
    apt-utils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Configurar repositório R
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7 && \
    add-apt-repository "deb $CRAN_MIRROR/bin/linux/debian buster-cran40/" && \
    apt-get update && \
    apt-get install -y --allow-unauthenticated --no-install-recommends r-base

# Configurar permissões do R
RUN chmod -R 777 /usr/local/lib/R/

# Instalar pacotes R básicos
RUN Rscript --vanilla -e 'install.packages(c("usethis", "shiny", "Rcpp", "V8", "sfsmisc", "clue", "lattice", "devtools", "MASS", "BiocManager"), repos="'$CRAN_MIRROR'", Ncpus=4)'

# Instalar pacotes R específicos do Bioconductor
RUN Rscript --vanilla -e 'BiocManager::install(c("igraph", "D2C", "pcalg", "glmnet", "mboost"), Ncpus=4, ask=FALSE)'

# Instalar pacotes R do CRAN
RUN Rscript --vanilla -e 'install.packages(c("bnlearn", "CAM", "SID", "kpcalg", "remotes"), repos="'$CRAN_MIRROR'", Ncpus=4)'

# Instalar pacotes R de arquivos específicos
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/randomForest/randomForest_4.6-14.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/fastICA/fastICA_1.2-2.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/SID/SID_1.0.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/CAM/CAM_1.0.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/sparsebnUtils_0.0.8.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/ccdrAlgorithm/ccdrAlgorithm_0.0.6.tar.gz", repos=NULL, type="source")'
RUN Rscript --vanilla -e 'install.packages("https://cran.r-project.org/src/contrib/Archive/sparsebn/sparsebn_0.1.2.tar.gz", repos=NULL, type="source")'

# Instalar pacotes R do GitHub
RUN Rscript --vanilla -e 'library(devtools); install_github("cran/CAM")'
RUN Rscript --vanilla -e 'library(devtools); install_github("cran/momentchi2")'
RUN Rscript --vanilla -e 'library(devtools); install_github("Diviyan-Kalainathan/RCIT")'
RUN Rscript --vanilla -e 'library(devtools); install_github("cran/discretecdAlgorithm")'

# Instalar pacotes R restantes
RUN Rscript --vanilla -e 'install.packages("discretecdAlgorithm", repos="'$CRAN_MIRROR'", Ncpus=4)'

# Configurar ambiente Python
WORKDIR /app

# Copiar requirements
COPY causal-nest/requirements.txt ./requirements1.txt
COPY LTVHub/LTVHub/requirements.txt ./requirements2.txt



# AGORA SIM copiar e executar o script
COPY combine_requirements.py ./
RUN pip install --no-cache-dir packaging
RUN python combine_requirements.py

RUN ls -la final_requirements.txt && head -5 final_requirements.txt

# Instalar pip compatível
RUN python -m pip install --no-cache-dir "pip<24.1"

# Instalar dependências básicas primeiro para evitar conflitos
RUN python -m pip install --no-cache-dir \
    numpy==1.26.1 \
    pandas==2.1.2 \
    scikit-learn==1.3.2 \
    packaging>=20.0

# Instalar outros pacotes
RUN python -m pip install --no-cache-dir -r final_requirements.txt || \
    (echo "Alguns pacotes falharam, tentando instalação individual..." && \
    while read line; do \
        python -m pip install --no-cache-dir "$line" || echo "Falha em: $line"; \
    done < final_requirements.txt)

# Instalar pacotes problemáticos manualmente se necessário
RUN python -m pip install --no-cache-dir \
    "torch>=2.1.0" \
    "mlflow<2.0" \
    "learntools-dados-ufv" || echo "Pacotes opcionais falharam"

# Atualizar pip e instalar Jupyter
# Atualizar pip e instalar JupyterLAB (em vez de notebook)
RUN python -m pip install --no-cache-dir --upgrade "pip>=24.1" && \
    pip install --no-cache-dir jupyterlab

# Opcional: remover pacotes do notebook tradicional se existirem
RUN pip uninstall -y notebook || true

# Verificar a instalação do JupyterLab
RUN python -c "import jupyterlab; print(f'JupyterLab version: {jupyterlab.__version__}')" || \
    echo "JupyterLab import check failed"

# Limpar arquivos temporários
RUN rm -f requirements1.txt requirements2.txt final_requirements.txt

# Copiar código
COPY causal-nest/ ./causal-nest
COPY LTVHub/ ./LTVHub

WORKDIR /app/causal-nest

CMD ["bash"]