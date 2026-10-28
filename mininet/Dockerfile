FROM p4lang/p4c:latest

USER root

ARG DEBIAN_FRONTEND=noninteractive

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ethtool \
        iproute2 \
        iputils-ping \
        mininet \
        procps \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/sbin/policy-rc.d

WORKDIR /workspace

COPY . /workspace

RUN make test

ENTRYPOINT ["/usr/bin/python3", "mininet/lab.py"]
CMD ["--test"]
