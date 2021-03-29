# Use Ubuntu 20.04 Image
FROM ubuntu:20.04

WORKDIR /tmp

# No Interactive
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# Update Image
RUN apt-get update && apt-get upgrade -y && apt-get autoremove -y

# Install Package Builder
RUN apt-get install -y autoconf \
    automake \
    libtool \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    build-essential \
    zlib1g-dev \
    libcppunit-dev \
    libncurses-dev \
    libncurses5-dev \
    libsigc++-2.0-dev \
    wget \
    curl \
    nano \
    git

# Install XML-RPC
RUN wget -qO xmlrpc-c.tar.gz https://github.com/mirror/xmlrpc-c/archive/master.tar.gz \
    && tar -xf xmlrpc-c.tar.gz \
    && cd xmlrpc-c-master/stable \
    && ./configure --prefix=/usr/local --disable-wininet-client --disable-libwww-client --disable-abyss-server --disable-abyss-threads --disable-abyss-openssl --disable-cgi-server --disable-cplusplus \
    && make -j$(nproc) \
    && make install \
    && rm -rf xmlrpc-c{.tar.gz,-master} \
    && ldconfig \
    && echo -e "Installation XML-RPC Complete\n"

# Install LibTorrent
RUN wget -qO libtorrent.tar.gz http://rtorrent.net/downloads/libtorrent-0.13.8.tar.gz \
    && tar xf libtorrent.tar.gz \
    && cd $(tar tf libtorrent.tar.gz | head -1 | cut -f1 -d"/") \
    && ./configure --prefix=/usr/local --disable-debug --with-posix-fallocate \
    && make -j$(nproc) \
    && make install \
    && rm -rf libtorrent{.tar.gz,-$(tar tf libtorrent.tar.gz | grep -om1 "0.*[^/]")} \
    && ldconfig \
    && echo -e "Installation LibTorrent Complete\n"

# Install rTorrent
RUN wget -qO rtorrent.tar.gz http://rtorrent.net/downloads/rtorrent-0.9.8.tar.gz \
    && tar xf rtorrent.tar.gz \
    && cd $(tar tf rtorrent.tar.gz | head -1 | cut -f1 -d"/") \
    && ./configure --prefix=/usr/local --disable-debug --with-xmlrpc-c \
    && make -j$(nproc) \
    && make install \
    && rm -rf rtorrent{.tar.gz,-$(tar tf rtorrent.tar.gz | grep -om1 "0.*[^/]")} \
    && ldconfig \
    && echo -e "Installation rTorrent Complete\n"

# Install Nginx
RUN apt-get install -y nginx

EXPOSE 80