FROM ubuntu
RUN apt-get update \
  && apt-get install -y fio

VOLUME /tmp
WORKDIR /tmp
COPY ./fio.sh /
ENTRYPOINT ["/fio.sh"]
CMD ["fio"]