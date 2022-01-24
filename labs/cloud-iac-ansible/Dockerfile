FROM python:3.9-alpine3.14

RUN apk update && apk upgrade
RUN apk add --no-cache bash\
                       python3 \
                       pkgconfig \
                       git \
                       gcc \
                       openldap \
                       libcurl \
                       python2-dev \
                       gpgme-dev \
                       libc-dev \
    && rm -rf /var/cache/apk/*

WORKDIR /ansible
COPY ./requirements.txt ./

RUN pip3 install -r requirements.txt

ADD . .
