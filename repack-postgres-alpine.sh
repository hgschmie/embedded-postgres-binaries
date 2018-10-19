#!/bin/bash

DOCKER_OPTS=
LITE_OPT=false

while getopts "v:i:o:l" opt; do
    case $opt in
    v) VERSION=$OPTARG ;;
    i) IMG_NAME=$OPTARG ;;
    o) DOCKER_OPTS=$OPTARG ;;
    l) LITE_OPT=true ;;
    \?) exit 1 ;;
    esac
done

if [ -z "$VERSION" ] ; then
  echo "Version parameter is required!" && exit 1;
fi
if [ -z "$IMG_NAME" ] ; then
  echo "Docker image parameter is required!" && exit 1;
fi
if [[ "$VERSION" == 9.* ]] && [[ "$LITE_OPT" == true ]] ; then
  echo "Lite option is supported only for PostgreSQL 10 or later!" && exit 1;
fi

E2FS_ENABLED=$([[ ! "$VERSION" == 9.3.* ]] && echo true || echo false);
ICU_ENABLED=$([[ ! "$VERSION" == 9.* ]] && [[ ! "$LITE_OPT" == true ]] && echo true || echo false);

TRG_DIR=$PWD/bundle
mkdir -p $TRG_DIR

docker run -i --rm -v ${TRG_DIR}:/usr/local/pg-dist $DOCKER_OPTS $IMG_NAME /bin/sh -c "echo 'Starting building postgres binaries' \
    && apk add --no-cache \
        coreutils \
        ca-certificates \
        wget \
        tar \
        xz \
        gcc \
        make \
        libc-dev \
        icu-dev \
        util-linux-dev \
        libxml2-dev \
        libxslt-dev \
        openssl-dev \
        zlib-dev \
        perl-dev \
        python3-dev \
        tcl-dev \
        chrpath \
        \
    && if [ "$E2FS_ENABLED" = false ]; then \
        wget -O uuid.tar.gz 'https://www.mirrorservice.org/sites/ftp.ossp.org/pkg/lib/uuid/uuid-1.6.2.tar.gz' \
        && mkdir -p /usr/src/ossp-uuid \
        && tar -xf uuid.tar.gz -C /usr/src/ossp-uuid --strip-components 1 \
        && cd /usr/src/ossp-uuid \
        && wget -O config.guess 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' \
        && wget -O config.sub 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' \
        && ./configure --prefix=/usr/local \
        && make -j\$(nproc) \
        && make install \
        && cp --no-dereference /usr/local/lib/libuuid.* /lib; \
       fi \
       \
    && wget -O postgresql.tar.bz2 'https://ftp.postgresql.org/pub/source/v$VERSION/postgresql-$VERSION.tar.bz2' \
    && mkdir -p /usr/src/postgresql \
    && tar -xf postgresql.tar.bz2 -C /usr/src/postgresql --strip-components 1 \
    && cd /usr/src/postgresql \
    && wget -O config/config.guess 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' \
    && wget -O config/config.sub 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' \
    && ./configure \
        CFLAGS='-O2' \
        PYTHON=/usr/bin/python3 \
        --prefix=/usr/local/pg-build \
        --enable-integer-datetimes \
        --enable-thread-safety \
        \$([ "$E2FS_ENABLED" = true ] && echo '--with-uuid=e2fs' || echo '--with-ossp-uuid') \
        --with-gnu-ld \
        --with-includes=/usr/local/include \
        --with-libraries=/usr/local/lib \
        \$([ "$ICU_ENABLED" = true ] && echo '--with-icu') \
        --with-libxml \
        --with-libxslt \
        --with-openssl \
        --with-perl \
        --with-python \
        --with-tcl \
        --without-readline \
    && make -j\$(nproc) world \
    && make install-world \
    && make -C contrib install \
    \
    && cd /usr/local/pg-build \
    && cp /lib/libuuid.so.1 /lib/libz.so.1 /usr/lib/libssl.so /usr/lib/libcrypto.so /usr/lib/libxml2.so.2 /usr/lib/libxslt.so.1 ./lib \
    && if [ "$ICU_ENABLED" = true ]; then cp --no-dereference /usr/lib/libicudata.so* /usr/lib/libicuuc.so* /usr/lib/libicui18n.so* ./lib; fi \
    && find ./bin -type f \( -name 'initdb' -o -name 'pg_ctl' -o -name 'postgres' \) -print0 | xargs -0 -n1 chrpath -r '\$ORIGIN/../lib' \
    && tar -cJvf /usr/local/pg-dist/postgres-linux-alpine_linux.txz --hard-dereference \
        share/postgresql \
        lib \
        bin/initdb \
        bin/pg_ctl \
        bin/postgres"