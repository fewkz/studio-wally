# syntax = docker/dockerfile:1.4
FROM debian:stable-20220912-slim AS download-deps
RUN apt-get update
RUN apt-get install -y wget unzip

RUN wget -q https://github.com/rojo-rbx/rojo/releases/download/v7.2.1/rojo-7.2.1-linux.zip
RUN unzip rojo-7.2.1-linux.zip
RUN wget -q https://github.com/UpliftGames/wally/releases/download/v0.3.1/wally-0.3.1-linux.zip
RUN unzip wally-0.3.1-linux.zip
RUN wget -q https://github.com/JohnnyMorganz/wally-package-types/releases/download/v1.1.1/wally-package-types-linux.zip
RUN unzip wally-package-types-linux.zip

FROM debian:stable-20220912-slim

RUN apt-get update
RUN apt-get install -y ca-certificates


COPY --from=download-deps /rojo /bin/rojo
COPY --from=download-deps /wally /bin/wally
COPY --from=download-deps /wally-package-types /bin/wally-package-types
RUN chmod +x /bin/wally

COPY ./base-project/* /srv/project/

WORKDIR /srv/project
COPY wally-server-startup.sh /srv/project/
RUN chmod +x wally-server-startup.sh
ENTRYPOINT [ "./wally-server-startup.sh" ]