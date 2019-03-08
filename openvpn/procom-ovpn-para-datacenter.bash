#!/bin/bash
tput clear

main_menu()
{
until [ option = 0 ]; do
unset empresa
read -p "
============================
1.) Listar empresas
2.) Listar accesos
3.) Alta empresa
4.) Alta acceso
5.) Baja acceso
6.) Limpiar consola
7.) Agregar redes
8.) Alta acceso bulk
9.) Listar clientes conectados
10.) Detalle empresas
11.) Migrar empresa
0.) Exit
Enter choice: " option
echo
case $option in

    1) lista_empresas;;
    2) lista_accesos;;
    3) alta_empresa;;
    4) alta_acceso;;
    5) baja_acceso;;
    6) limpia_consola;;
    7) agrega_server;;
    8) alta_acceso_bulk;;
    9) lista_conectados;;
    10) detalle_empresas;;
    11) migrar_empresa;;
    0) exit;;
    *) echo -e "\e[31mPor favor ingrese una opcion valida\e[0m";;

esac
done
}

lista_empresas()
{
docker exec -it ovpn.db sqlite3 /database/ovpn.db '.header on' '.mode column' '.width 60, 6' 'SELECT nombre, puerto FROM empresa;'
main_menu
}

lista_accesos()
{
echo -e "\e[34m================ Lista Accesos ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
				docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn ovpn_listclients
				main_menu
        else
				echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

alta_empresa()
{
echo -e "\e[34m================ Alta Empresa ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
echo -e "\e[34mIngrese el puerto asignado a $empresa: \e[0m"
read port

if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
                echo -e "\e[31mla empresa $empresa ya se encuentra dada de alta.\e[0m"
        else
                if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE puerto='$port' COLLATE NOCASE);" | grep -q '1';
                        then
                                echo -e "\e[31mel puerto $port ya se encuentra utilizado por otra empresa.\e[0m"
                        else
                                read -p $'\e[34mDesea forzar a los clientes a utilizar un servidor DNS privado? (y/n):\e[0m' yn
                                        case $yn in
                                                [Yy]* ) alta_empresa_con_dns;;
                                                [Nn]* ) alta_empresa_sin_dns;;
                                                    * ) echo -e "\e[31mPor favor responda y o n .\e[0m";;
                                        esac
                fi
fi
}

alta_empresa_sin_dns ()
{
echo -e "\e[33mCargando config de servidor OpenVpn.\e[0m"
docker run \
-v $empresa.openvpn:/etc/openvpn \
--rm kylemanna/openvpn ovpn_genconfig \
-u tcp://$empresa:$port \
-s 172.30.0.0/16 \
-d -D -N \
echo ""
echo ""
echo -e "\e[33mGenerando llaves para servidor OpenVpn\e[0m"
docker run -v $empresa.openvpn:/etc/openvpn \
--rm -it kylemanna/openvpn ovpn_initpki nopass 


echo -e "\e[33mRetocando config\e[0m"
docker run -v $empresa.openvpn:/etc/openvpn \
--rm -it kylemanna/openvpn sed -i '/push block-outside-dns/d' /etc/openvpn/openvpn.conf

echo -e "\e[33mCreando contenedor de servicio OpenVpn\e[0m"
docker run -d \
--name $empresa.openvpn \
-v $empresa.openvpn:/etc/openvpn \
-p $port:1194/tcp --cap-add=NET_ADMIN \
--restart unless-stopped \
kylemanna/openvpn

# We need to reload iptables rules after every restart and every new network added.
docker exec -d $empresa.openvpn /bin/bash -c "sed -i '3ifi' /usr/local/bin/ovpn_run ; sed -i '3iiptables-restore /etc/openvpn/iptables.rules.v4' /usr/local/bin/ovpn_run ; sed -i '3iif [  -f /etc/openvpn/iptables.rules.v4 ]; then' /usr/local/bin/ovpn_run ; sed -i '3i# Load iptables rules' /usr/local/bin/ovpn_run" 

# Add iptables rules to this container, we accept only servers specified, everything else is dropped
docker exec -d $empresa.openvpn /bin/bash -c "iptables -i tun0 -A FORWARD -j DROP"

# save those iptables changes
docker exec -d $empresa.openvpn /bin/bash -c "iptables-save > /etc/openvpn/iptables.rules.v4"

docker exec -it ovpn.db sqlite3 /database/ovpn.db "INSERT INTO EMPRESA (NOMBRE,PUERTO) VALUES ('$empresa', '$port');"

docker run -v ovpn.cifs:/perfiles --rm -it alpine sh -c "mkdir /perfiles/$empresa" && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare"
}

alta_empresa_con_dns()
{
echo -e "\e[34mIngrese la ip del servidor DNS que usara $empresa (ej: 192.168.121.6): \e[0m"
read ipdns
echo -e "\e[34mIngrese el nombre de dominio de busqueda (ej: dominio.local): \e[0m"
read domaindns


echo -e "\e[33mCargando config de servidor OpenVpn.\e[0m"
docker run \
-v $empresa.openvpn:/etc/openvpn \
--rm kylemanna/openvpn ovpn_genconfig \
-u tcp://$empresa:$port \
-s 172.30.0.0/16 \
-d -D -N \
-p "route $ippriv $mask"

echo ""
echo ""
echo -e "\e[33mGenerando llaves para servidor OpenVpn\e[0m"
docker run -v $empresa.openvpn:/etc/openvpn \
--rm -it kylemanna/openvpn ovpn_initpki nopass

docker run -v $empresa.openvpn:/etc/openvpn \
--rm -it kylemanna/openvpn bash -c 'echo push "\""dhcp-option DNS '$ipdns'"\""  >> /etc/openvpn/openvpn.conf'

docker run -v $empresa.openvpn:/etc/openvpn \
--rm -it kylemanna/openvpn bash -c 'echo push "\""dhcp-option DOMAIN '$domaindns'"\""  >> /etc/openvpn/openvpn.conf'

echo -e "\e[33mCreando contenedor de servicio OpenVpn\e[0m"
docker run -d \
--name $empresa.openvpn \
-v $empresa.openvpn:/etc/openvpn \
-p $port:1194/tcp --cap-add=NET_ADMIN \
--restart unless-stopped \
kylemanna/openvpn

# We need to reload iptables rules after every restart and every new network added.
docker exec -d $empresa.openvpn /bin/bash -c "sed -i '3ifi' /usr/local/bin/ovpn_run ; sed -i '3iiptables-restore /etc/openvpn/iptables.rules.v4' /usr/local/bin/ovpn_run ; sed -i '3iif [  -f /etc/openvpn/iptables.rules.v4 ]; then' /usr/local/bin/ovpn_run ; sed -i '3i# Load iptables rules' /usr/local/bin/ovpn_run" 

# Add iptables rules to this container, we accept only servers specified, everything else is dropped
docker exec -d $empresa.openvpn /bin/bash -c "iptables -i tun0 -A FORWARD -j DROP"

# save those iptables changes
docker exec -d $empresa.openvpn /bin/bash -c "iptables-save > /etc/openvpn/iptables.rules.v4"

docker exec -it ovpn.db sqlite3 /database/ovpn.db "INSERT INTO EMPRESA (NOMBRE,PUERTO) VALUES ('$empresa', '$port');"

docker run -v ovpn.cifs:/perfiles --rm -it alpine sh -c "mkdir /perfiles/$empresa" && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare"
}

alta_acceso()
{
echo -e "\e[34m================ Alta Acceso ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
echo -e "\e[34mIngrese el numero de acceso: \e[0m"
read acceso
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
                read -p $'\e[34mQuiere que el perfil solicite password? (y/n): \e[0m' yn
    case $yn in
        [Yy]* ) docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $empresa-$acceso;;
        [Nn]* ) docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $empresa-$acceso nopass;;
        * ) echo -e "\e[31mPor favor responda y o n .\e[0m";;
    esac
				docker run -v ovpn.cifs:/perfiles -v $empresa.openvpn:/etc/openvpn -v openvpn.files.bin:/usr/local/bin --rm -it kylemanna/openvpn ovpn_getclient $empresa-$acceso combined-save && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare"
        else
                echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

baja_acceso()
{
echo -e "\e[34m================ Baja Acceso ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
echo -e "\e[34mIngrese el numero de acceso: \e[0m"
read acceso
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
read -p $'\e[31mVoy a dar de baja el acceso indicado estas seguro? (y/n) \e[0m' yn
    case $yn in
        [Yy]* ) docker run -v ovpn.cifs:/perfiles -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa revoke $empresa-$acceso && docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa gen-crl && docker run -v ovpn.cifs:/perfiles --rm -it alpine sh -c "mv /perfiles/$empresa/$empresa-$acceso.ovpn /perfiles/$empresa/[REVOKED]$empresa-$acceso.ovpn" && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare" ;;
		[Nn]* ) echo -e "\e[31mTarea cancelada\e[0m" && exit;;
        * ) echo -e "\e[31mPor favor responda y o n .\e[0m";;
    esac
        else
                echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

limpia_consola()
{
tput clear
}

agrega_server()
{
echo -e "\e[34m================ Agregar Server ================\e[0m"
echo ""
if [ -z "$empresa" ];
        then
                echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
				read empresa
				if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
					then
						agrega_server
					else
						echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
						main_menu
			    fi 
        else
                echo -e "\e[34mIngrese la subred (privada) que usa o usara $empresa (ej: 192.168.121.0): \e[0m"
                read ippriv
                echo -e "\e[34mIngrese la mascara para la subred definida (ej: 255.255.255.0): \e[0m"
                read mask
                docker exec $empresa.openvpn bash -c "echo push \'route $ippriv $mask\' >> /etc/openvpn/openvpn.conf";
                docker exec -d $empresa.openvpn /bin/bash -c "iptables -i tun0 -I FORWARD 1 -d $ippriv/$mask -j ACCEPT"
                echo -e "\e[34mQuiere agregar otro servidor a $empresa? (y/n): \e[0m"
fi
read answer
if echo "$answer" | grep -iq "^y" ;then
    agrega_server
else
   echo "Guardando cambios en iptables..." ; 
   docker exec -d $empresa.openvpn /bin/bash -c "iptables-save > /etc/openvpn/iptables.rules.v4" ;     
   echo -e "\e[31mSus cambios no surtiran efecto hasta que el contenedor de $empresa sea reinciado. Desea reiniciarlo ahora? CUIDADO! esto desconectara a los usuarios de $empresa momentaneamente (y/n)\e[0m"
   read answer
                if echo "$answer" | grep -iq "^y" ;then
						docker restart $empresa.openvpn
						main_menu
                else
						echo -e "\e[31mReinicio no efectuado. Recuerde que sus cambios no surtiran efecto hasta tanto reinicie el contenedor\e[0m"
						main_menu
				fi
fi
}

alta_acceso_bulk()
{
echo -e "\e[34m================ Alta Acceso Bulk ================\e[0m"
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
echo -e "\e[34mIngrese el primer numero de acceso: \e[0m"
read primer_acceso
echo -e "\e[34mIngrese el utlimo numero de acceso: \e[0m"
read ultimo_acceso
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
                read -p $'\e[34mQuiere que el perfil solicite password? (y/n): \e[0m' yn
    case $yn in
        [Yy]* ) for i in $(seq $primer_acceso $ultimo_acceso); do docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $empresa-$i ; done;;
        [Nn]* ) for i in $(seq $primer_acceso $ultimo_acceso); do docker run -v $empresa.openvpn:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $empresa-$i nopass ; done;;
        * ) echo -e "\e[31mPor favor responda y o n .\e[0m";;
    esac
                for i in $(seq $primer_acceso $ultimo_acceso); do docker run -v ovpn.cifs:/perfiles -v $empresa.openvpn:/etc/openvpn -v openvpn.files.bin:/usr/local/bin --rm -it kylemanna/openvpn ovpn_getclient $empresa-$i combined-save ; done && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare"
        else
                echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

lista_conectados()
{
echo -e "\e[34m================ Lista Conectados ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
docker exec -it $empresa.openvpn more /tmp/openvpn-status.log
main_menu
        else
                echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

detalle_empresas()
{
echo -e "\e[34m================ Detalle empresas ================\e[0m"
echo ""
echo -e "\e[34mIngrese nombre de la empresa: \e[0m"
read empresa
if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
echo -e "\e[34m================ Redes enrutadas para $empresa ================\e[0m"
docker exec -it $empresa.openvpn tail /etc/openvpn/openvpn.conf | grep route | cut  -d' ' -f3,4 | sed 's/"//' | sed "s/'//"
main_menu
        else
                echo -e "\e[31mla empresa $empresa no se encuentra dada de alta.\e[0m"
fi
}

migrar_empresa()
{

if [ "$EUID" -ne 0 ]
  then echo -e "\e[31mParece que no tenes los permisos necesarios, tal vez un "sudo" ayude?\e[0m"
  main_menu
fi

echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"
echo -e "\e[31m CUIDADO!!!! \e[0m"

echo -e "Esta opcion va a dar de baja el contenedor que seleccione y lo dara de alta en MsOffice"
sleep 2
echo -e ""
echo -e ""
echo -e "\e[34mEmpresa                                  Puerto          Servidor\e[0m"
echo -e "\e[34m========================================================================\e[0m"
ssh root@192.168.121.27 'cat /openvpn-dc/empresas.txt'
echo -e "\e[31m================ MIGRAR EMPRESA ================\e[0m"
echo ""
echo -e "Todas estas empresas estan disponibles, cual quiere migrar?"
read empresa
port=$(ssh root@192.168.121.27 'cat /openvpn-dc/empresas.txt | grep '$empresa'' | awk '{print $2}')
echo "Ok, veo que el puerto de $empresa es $port"
echo "Ahora voy a crear el contenedor $empresa en MSOFFICE con el puerto $port"

if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE nombre='$empresa' COLLATE NOCASE);" | grep -q '1';
        then
                echo -e "\e[31mla empresa $empresa ya se encuentra dada de alta.\e[0m"
        else
                if docker exec -it ovpn.db sqlite3 /database/ovpn.db "SELECT EXISTS(SELECT 1 FROM empresa WHERE puerto='$port' COLLATE NOCASE);" | grep -q '1';
                        then
                                echo -e "\e[31mel puerto $port ya se encuentra utilizado por otra empresa.\e[0m"
                        else
                                read -p $'\e[34mEs esto correcto? (y/n): \e[0m' yn
                                        case $yn in
                                                [Yy]* ) migrar_ya;;
                                                [Nn]* ) echo -e "\e[31mTarea cancelada\e[0m" && main_menu;;
                                                    * ) echo -e "\e[31mPor favor responda y o n .\e[0m";;
                                        esac
                fi
fi
}

migrar_ya()
{
echo -e "\e[33mCreando contenedor de servicio OpenVpn\e[0m"
docker run -d \
--name $empresa.openvpn \
-v $empresa.openvpn:/etc/openvpn \
-p $port:1194/tcp --cap-add=NET_ADMIN \
--restart unless-stopped \
kylemanna/openvpn

echo -e "\e[33mCopiando archivos de contenedor en IPLAN\e[0m"
sudo scp -r root@192.168.121.27:/var/lib/docker/volumes/$empresa.openvpn/_data /var/lib/docker/volumes/$empresa.openvpn

echo -e "\e[33mRetocando config de contenedor en IPLAN\e[0m"
sed -i 's/\<push\>/& "/' /var/lib/docker/volumes/$empresa.openvpn/_data/openvpn.conf
sed -i 's/push.*/&"/g' /var/lib/docker/volumes/$empresa.openvpn/_data/openvpn.conf

echo -e "\e[33mIniciando en el nuevo contenedor\e[0m"
docker restart $empresa.openvpn

echo -e "\e[33mConfigurando IPTABLES en el nuevo contenedor\e[0m"

# We need to reload iptables rules after every restart and every new network added.
docker exec -d $empresa.openvpn /bin/bash -c "sed -i '3ifi' /usr/local/bin/ovpn_run ; sed -i '3iiptables-restore /etc/openvpn/iptables.rules.v4' /usr/local/bin/ovpn_run ; sed -i '3iif [  -f /etc/openvpn/iptables.rules.v4 ]; then' /usr/local/bin/ovpn_run ; sed -i '3i# Load iptables rules' /usr/local/bin/ovpn_run" 

# Add iptables rules to this container, we accept only servers specified, everything else is dropped
docker exec -d $empresa.openvpn /bin/bash -c "iptables -i tun0 -A FORWARD -j DROP"

# save those iptables changes
docker exec -d $empresa.openvpn /bin/bash -c "iptables-save > /etc/openvpn/iptables.rules.v4"

echo -e "\e[33mCargando nueva empresa en la DB\e[0m"

docker exec -it ovpn.db sqlite3 /database/ovpn.db "INSERT INTO EMPRESA (NOMBRE,PUERTO) VALUES ('$empresa', '$port');"

echo -e "\e[33mCreando folder de empresa y sincronizando con server cifs\e[0m"

docker run -v ovpn.cifs:/perfiles --rm -it alpine sh -c "mkdir /perfiles/$empresa" && docker exec ovpn.cifs /bin/sh -c "rsync -a /mnt/openvpn/ /mnt/winshare"

echo -e "\e[33mTengo que bloquear el acceso a ovpn01.procomisp.com.ar y ovpn02.procomisp.com.ar en el mikrotik de IPLAN\e[0m"

ssh -o ConnectTimeout=30 -l ovpnmigrate -i /root/.ssh/id_rsa 192.168.121.3 "/ip firewall filter add protocol=tcp dst-port="\""$port"\"" chain=input action=drop comment="\""["$empresa"] [MIGRADO] procom docker openvpn"\"" place-before=0"

echo -e "\e[33mAhora voy a detener el contenedor $empresa en IPLAN\e[0m"

ssh root@192.168.121.27 "docker stop "\""$empresa"\"".openvpn"

echo -e "\e[33mReiniciar contenedor $empresa en MSOFFICE\e[0m"

docker restart $empresa.openvpn

echo -e "\e[33mTodo listo, fijate entre los usuarios coenctados en $empresa para ver si ya estan conectando\e[0m"

}

main_menu
