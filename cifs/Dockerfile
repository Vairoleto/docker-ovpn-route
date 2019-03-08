FROM alpine
ARG WINSHARE_PATH=local
ARG USER=local
ARG PASSWD=local 
ENV WINSHARE_PATH ${WINSHARE_PATH}
ENV USER ${USER}
ENV PASSWD ${PASSWD}
RUN mkdir /mnt/winshare && \
    mkdir /mnt/openvpn && \
    apk update && \
    apk add cifs-utils && \
    apk add rsync && \
    echo "${WINSHARE_PATH}    /mnt/winshare    cifs    uid=0,gid=0,user=${USER},password=${PASSWD},_netdev 0 0" >> /etc/fstab
CMD mount -a ; sleep 365d
