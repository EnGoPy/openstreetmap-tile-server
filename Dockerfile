FROM ubuntu:18.04

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/

# Set up environment
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install dependencies
RUN apt-get update \
  && apt-get install -y wget gnupg2 lsb-core apt-transport-https ca-certificates curl \
  && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && echo "deb [ trusted=yes ] https://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list \
  && wget --quiet -O - https://deb.nodesource.com/setup_10.x | bash - \
  && apt-get update \
  && apt-get install -y nodejs

RUN apt-get install -y --no-install-recommends \
  apache2 \
  apache2-dev \
  autoconf \
  build-essential \
  bzip2 \
  cmake \
  cron \
  fonts-noto-cjk \
  fonts-noto-hinted \
  fonts-noto-unhinted \
  gcc \
  gdal-bin \
  git-core \
  libagg-dev \
  libboost-filesystem-dev \
  libboost-system-dev \
  libbz2-dev \
  libcairo-dev \
  libcairomm-1.0-dev \
  libexpat1-dev \
  libfreetype6-dev \
  libgdal-dev \
  libgeos++-dev \
  libgeos-dev \
  libgeotiff-epsg \
  libicu-dev \
  liblua5.3-dev \
  libmapnik-dev \
  libpq-dev \
  libproj-dev \
  libprotobuf-c0-dev \
  libtiff5-dev \
  libtool \
  libxml2-dev \
  lua5.3 \
  make \
  mapnik-utils \
  node-gyp \
  osmium-tool \
  osmosis \
  postgis \
  postgresql-12 \
  postgresql-contrib-12 \
  postgresql-server-dev-12 \
  protobuf-c-compiler \
  python3-mapnik \
  python3-lxml \
  python3-psycopg2 \
  python3-shapely \
  sudo \
  tar \
  ttf-unifont \
  unzip \
  wget \
  zlib1g-dev \
  nano \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

# Set up PostGIS
RUN wget https://download.osgeo.org/postgis/source/postgis-3.1.1.tar.gz -O postgis.tar.gz \
 && mkdir -p postgis_src \
 && tar -xvzf postgis.tar.gz --strip 1 -C postgis_src \
 && rm postgis.tar.gz \
 && cd postgis_src \
 && ./configure \
 && make -j $(nproc) \
 && make -j $(nproc) install \
 && cd .. && rm -rf postgis_src

# Set up renderer user
RUN adduser --disabled-password --gecos "" renderer

# Install latest osm2pgsql
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone -b master https://github.com/openstreetmap/osm2pgsql.git --depth 1 \
 && cd /home/renderer/src/osm2pgsql \
 && rm -rf .git \
 && mkdir build \
 && cd build \
 && cmake .. \
 && make -j $(nproc) \
 && make -j $(nproc) install \
 && mkdir /nodes \
 && chown renderer:renderer /nodes \
 && rm -rf /home/renderer/src/osm2pgsql

# Install mod_tile and renderd
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git --depth 1 \
 && cd mod_tile \
 && rm -rf .git \
 && ./autogen.sh \
 && ./configure \
 && make -j $(nproc) \
 && make -j $(nproc) install \
 && make -j $(nproc) install-mod_tile \
 && ldconfig \
 && cd ..

# Configure stylesheet
RUN mkdir -p /home/renderer/src \
 && npm install -g carto@0.18.2 \
 # generate general AH style .xml
 && mkdir -p /home/renderer/src/general \
 && cd /home/renderer/src/general \
 && git clone --single-branch --branch calm_drive_520 https://github.com/EnGoPy/openstreetmap-carto.git --depth 1  \
 && cd ./openstreetmap-carto \
 && rm -rf .git \
 && carto project.mml > mapnik.xml \
# generate driver_day style .xml
 && mkdir -p /home/renderer/src/driver_day \
 && cd /home/renderer/src/driver_day \
 && git clone --single-branch --branch driver_day https://github.com/EnGoPy/openstreetmap-carto.git --depth 1  \
 && cd ./openstreetmap-carto \
 && rm -rf .git \
 && carto project.mml > mapnik.xml \
# download general 5.2.0 branch
 && cd /home/renderer/src \
 && git clone --single-branch --branch v5.2.0 https://github.com/gravitystorm/openstreetmap-carto.git --depth 1 \
# copy mapnik.xml's to working directory
 && cp -p  /home/renderer/src/general/openstreetmap-carto/mapnik.xml /home/renderer/src/openstreetmap-carto/mapnik_general.xml \
 && cp -p  /home/renderer/src/driver_day/openstreetmap-carto/mapnik.xml /home/renderer/src/openstreetmap-carto/mapnik_driver_day.xml \
 && cp -p  /home/renderer/src/driver_day/openstreetmap-carto/mapnik.xml /home/renderer/src/openstreetmap-carto/mapnik_128.xml \
 && cp -p  /home/renderer/src/driver_day/openstreetmap-carto/mapnik.xml /home/renderer/src/openstreetmap-carto/mapnik_512.xml \
# remove old repositories data
 && rm -rf /home/renderer/src/general \
 && rm -rf /home/renderer/src/driver_day \
# remove old repositories
 && cd /home/renderer/src/openstreetmap-carto \
 && rm -rf .git \
 && carto project.mml > mapnik.xml \
 && scripts/get-shapefiles.py \
 && rm /home/renderer/src/openstreetmap-carto/data/*.zip

# Configure renderd
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf \
 && sed -i 's/\/truetype//g' /usr/local/etc/renderd.conf \
 && sed -i 's/hot/osm_tiles/g' /usr/local/etc/renderd.conf

# Configure Apache
RUN mkdir /var/lib/mod_tile \
 && chown renderer /var/lib/mod_tile \
 && cp -pr /var/lib/mod_tile /var/lib/mod_tile_driver_day \
 && cp -pr /var/lib/mod_tile /var/lib/mod_tile_general \
 && cp -pr /var/lib/mod_tile /var/lib/mod_tile_128 \
 && cp -pr /var/lib/mod_tile /var/lib/mod_tile_512 \
 && mkdir /var/run/renderd \
 && chown renderer /var/run/renderd \
 && echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
 && echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
 && a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY leaflet-demo.html /var/www/html/index.html
COPY driver_day.html /var/www/html/driver_day.html
COPY driver_night.html /var/www/html/driver_night.html
COPY passenger_day.html /var/www/html/passenger_day.html
COPY passenger_night.html /var/www/html/passenger_night.html
COPY 128.html /var/www/html/128.html
COPY 512.html /var/www/html/512.html
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

#Configure for different styles
COPY custom_style_configuration.txt /usr/local/etc
RUN cat /usr/local/etc/custom_style_configuration.txt >> /usr/local/etc/renderd.conf

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/12/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
 && chown postgres:postgres /etc/postgresql/12/main/postgresql.custom.conf.tmpl \
 && echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/12/main/pg_hba.conf \
 && echo "host all all ::/0 md5" >> /etc/postgresql/12/main/pg_hba.conf

# Copy update scripts
COPY openstreetmap-tiles-update-expire /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire \
 && mkdir /var/log/tiles \
 && chmod a+rw /var/log/tiles \
 && ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
 && echo "*  *    * * *   renderer    openstreetmap-tiles-update-expire\n" >> /etc/crontab

# Install trim_osc.py helper script
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone https://github.com/zverik/regional \
 && cd regional \
 && git checkout 889d630a1e1a1bacabdd1dad6e17b49e7d58cd4b \
 && rm -rf .git \
 && chmod u+x /home/renderer/src/regional/trim_osc.py

# Start running
COPY run.sh /
COPY indexes.sql /
ENTRYPOINT ["/run.sh"]
CMD []

EXPOSE 80 5432
