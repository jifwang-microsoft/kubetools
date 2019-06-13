FROM ubuntu
RUN apt-get update \
  && apt-get install -y fio

VOLUME /tmp
WORKDIR /tmp
COPY ./fio_run.sh /
ENTRYPOINT ["/fio_run.sh"]
CMD ["fio"]