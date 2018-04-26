FROM ubuntu:16.04
ARG SCRIPT_NAME
ARG SCRIPT_URL
ARG SCRIPT_PARAM1
ARG SCRIPT_PARAM2
ARG SCRIPT_PARAM3
ARG SCRIPT_PARAM4
ARG SCRIPT_PARAM5
ARG SCRIPT_PARAM6
ARG SCRIPT_PARAM7
ARG SCRIPT_PARAM8
ARG SCRIPT_PARAM9
ARG SCRIPT_PARAM10

ENV DEBIAN_FRONTEND=noninteractive \ 

    LANG=en_US.UTF-8 \ 

    TERM=xterm 

RUN echo "export > /etc/envvars" >> /root/.bashrc && \ 

    echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" | tee -a /root/.bashrc /etc/bash.bashrc && \ 

    echo "alias tcurrent='tail /var/log/*/current -f'" | tee -a /root/.bashrc /etc/bash.bashrc 

  

RUN apt-get update 

RUN apt-get install -y locales && locale-gen en_US en_US.UTF-8 

  

# Runit 

RUN apt-get install -y --no-install-recommends runit 

CMD export > /etc/envvars && /usr/sbin/runsvdir-start 

  

# Utilities 

RUN apt-get install -y --no-install-recommends apt-transport-https vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh rsync 



ENV SCRIPT_NAME=$SCRIPT_NAME
ENV SCRIPT_URL=$SCRIPT_URL
ENV SCRIPT_PARAM1=$SCRIPT_PARAM1
ENV SCRIPT_PARAM2=$SCRIPT_PARAM2
ENV SCRIPT_PARAM3=$SCRIPT_PARAM3
ENV SCRIPT_PARAM4=$SCRIPT_PARAM4
ENV SCRIPT_PARAM5=$SCRIPT_PARAM5
ENV SCRIPT_PARAM6=$SCRIPT_PARAM6
ENV SCRIPT_PARAM7=$SCRIPT_PARAM7
ENV SCRIPT_PARAM8=$SCRIPT_PARAM8
ENV SCRIPT_PARAM9=$SCRIPT_PARAM9
ENV SCRIPT_PARAM10=$SCRIPT_PARAM10


CMD echo $SCRIPT_NAME
CMD wget $SCRIPT_URL -O $SCRIPT_NAME && sh $SCRIPT_NAME $SCRIPT_PARAM1 $SCRIPT_PARAM2 $SCRIPT_PARAM3 $SCRIPT_PARAM4 $SCRIPT_PARAM5 $SCRIPT_PARAM6 $SCRIPT_PARAM7 $SCRIPT_PARAM8 $SCRIPT_PARAM9 $SCRIPT_PARAM10
