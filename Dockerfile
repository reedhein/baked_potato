FROM ubuntu:16.04
MAINTAINER Doug Headley <doug@reedhein.com>

LABEL container=kitten_klicker

RUN apt-get update
RUN apt-get upgrade -y

RUN apt-get install -y build-essential git bcrypt libtool openssl automake curl \
  zlib1g-dev zlib1g zlibc ruby-dev libssl-dev libyaml-dev libsqlite3-0 \
  libsqlite3-dev libxml2-dev libxslt-dev autoconf libc6-dev sqlite3 \
  libreadline-dev libreadline6 libreadline6-dev libgmp-dev libgmp3-dev \
  ncurses-dev g++ bison gcc libmagickwand-dev apt-utils

ENV CONFIGURE_OPTS --disable-install-rdoc

ENV RUBY_VERSION=2.3.1
RUN curl -O http://ftp.ruby-lang.org/pub/ruby/2.3/ruby-${RUBY_VERSION}.tar.gz && \
    tar -zxvf ruby-${RUBY_VERSION}.tar.gz && \
    cd ruby-${RUBY_VERSION} && \
    ./configure --disable-install-doc --enable-shared && \
    make && \
    make install && \
    cd .. && \
    rm -r ruby-${RUBY_VERSION} ruby-${RUBY_VERSION}.tar.gz && \
    echo 'gem: --no-document' > /usr/local/etc/gemrcdoc

RUN apt-get install -y postgresql postgresql-client postgresql-contrib libpq-dev libpq5 postgresql-server-dev-9.5 iputils-ping nmap

RUN apt-get clean
# Clean up downloaded packages
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN gem install bundler

WORKDIR /tmp
ADD ./Gemfile Gemfile
ADD ./Gemfile.lock Gemfile.lock
RUN bundle install

ADD ./ /opt/kitten_klicker
WORKDIR /opt/kitten_klicker

EXPOSE 4545

CMD bundle exec ruby baked_potato.rb -o 0.0.0.0

