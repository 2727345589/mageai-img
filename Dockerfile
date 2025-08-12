FROM ubuntu:22.04
LABEL description="Deploy Mage on ECS with Python 3.12"
ARG FEATURE_BRANCH
USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 避免 apt 安装过程中的交互提示
ENV DEBIAN_FRONTEND=noninteractive

# 先更新系统并安装基础工具
RUN mkdir -p /etc/apt/keyrings && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
        curl \
        apt-transport-https \
        ca-certificates \
        gnupg2 \
        software-properties-common \
        krb5-config \
        libkrb5-dev \
        build-essential \
        git \
        libpq-dev \
        nfs-common \
        unixodbc-dev \
        graphviz \
        r-base && \
    # 添加 Microsoft ODBC Driver 18 for SQL Server 的源
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
        -o /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update -y && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql18 && \
    rm -rf /var/lib/apt/lists/*


# 安装 Python 3.12
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
      python3.12 \
      python3.12-dev \
      python3.12-venv \
      curl && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    pip3 install --no-cache-dir --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

# 配置 Microsoft SQL ODBC 驱动和 Node.js
RUN curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    NODE_MAJOR=20 && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

# 安装 R 依赖包
RUN R -e "install.packages('pacman', repos='http://cran.us.r-project.org')" && \
    R -e "install.packages('renv', repos='http://cran.us.r-project.org')"

# 安装 Python 依赖
RUN pip3 install --no-cache-dir sparkmagic && \
    mkdir -p ~/.sparkmagic && \
    curl https://raw.githubusercontent.com/jupyter-incubator/sparkmagic/master/sparkmagic/example_config.json > ~/.sparkmagic/config.json && \
    sed -i 's/localhost:8998/host.docker.internal:9999/g' ~/.sparkmagic/config.json && \
    jupyter-kernelspec install --user "$(pip3 show sparkmagic | grep Location | cut -d' ' -f2)/sparkmagic/kernels/pysparkkernel"

# Mage integrations 和其他相关包
RUN pip3 install --no-cache-dir \
    "git+https://github.com/wbond/oscrypto.git@d5f3437ed24257895ae1edd9e503cfb352e635a8" \
    "git+https://github.com/dremio-hub/arrow-flight-client-examples.git#egg=dremio-flight&subdirectory=python/dremio-flight" \
    "git+https://github.com/mage-ai/singer-python.git#egg=singer-python" \
    "git+https://github.com/mage-ai/dbt-mysql.git#egg=dbt-mysql" \
    "git+https://github.com/mage-ai/sqlglot#egg=sqlglot" \
    faster-fifo && \
    if [ -z "$FEATURE_BRANCH" ] || [ "$FEATURE_BRANCH" = "null" ]; then \
        pip3 install --no-cache-dir "git+https://github.com/mage-ai/mage-ai.git#egg=mage-integrations&subdirectory=mage_integrations"; \
    else \
        pip3 install --no-cache-dir "git+https://github.com/mage-ai/mage-ai.git@$FEATURE_BRANCH#egg=mage-integrations&subdirectory=mage_integrations"; \
    fi

# 安装 Mage 本体
COPY ./mage_ai/server/constants.py /tmp/constants.py
COPY ./requirements.txt /tmp/requirements.txt
RUN if [ -z "$FEATURE_BRANCH" ] || [ "$FEATURE_BRANCH" = "null" ] ; then \
        pip3 install --no-cache-dir -r /tmp/requirements.txt; \
    else \
        pip3 install --no-cache-dir -r /tmp/requirements.txt; \
    fi

# 启动脚本
COPY --chmod=0755 ./scripts/install_other_dependencies.py ./scripts/run_app.sh /app/

ENV MAGE_DATA_DIR="/home/src/mage_data"
ENV PYTHONPATH="${PYTHONPATH}:/home/src"
WORKDIR /home/src
EXPOSE 6789 7789

CMD ["/bin/sh", "-c", "/app/run_app.sh"]
