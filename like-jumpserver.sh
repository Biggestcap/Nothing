#!/bin/bash
# 此脚本对于运维来说是满级权限，可控制所有的主机。
# 主机列表
WEB01=10.0.0.7
WEB02=10.0.0.8
DB=10.0.0.51

# 定义主机列表函数
host(){
	echo -e "\t\t\t\t\033[2;34m1.$WEB01\033[0m"
	echo -e "\t\t\t\t\033[2;34m2.$WEB02\033[0m"
	echo -e "\t\t\t\t\033[2;34m3.$DB\033[0m"
	echo -e "\t\t\t\t\033[2;34m4.返回上一级.\033[0m"
}

# 定义登录角色函数
role(){
	echo -e "\t\t\t\t\033[2;34m1.ops\033[0m"
	echo -e "\t\t\t\t\033[2;34m2.dev\033[0m"
}

#定义开发可操作的范围
dev(){
	echo -e "\t\t\t\t\033[2;34m1.$WEB01\033[0m"
	echo -e "\t\t\t\t\033[2;34m2.返回上一级.\033[0m"
}
while true
do
	trap "" HUP TSTP INT
  role
  read -p "请输入你的身份序号: " num
  [ -z $num ] && echo -e "\t\t\t\033[2;31m序号不能为空,请输入以下序号。\033[0m" && continue
  echo ""
  [[ ! $num =~ ^[0-9]$ ]] && echo -e "\t\t\t\033[2;31m序号必须是[1-9]的整数" && continue
  echo ""
  if [ $num -eq 1 ];then
    i=0
    while true
    do
      [ $i -ge 3 ] && echo "密码错误三次，请60s后再重试！" && sleep 60
      read -s -p "请输入运维组的密码: " passwd
      echo ""
      [ -z $passwd ] && echo "密码不能为空" && continue
      if [ $passwd = ops666 ];then
  	      break
      else
	      let i++
	      echo "密码错误，请重新尝试输入."
	      continue
      fi
    done
    while true
    do
      host
      read -p "请选择你要连接的主机序号: " id
      [ -z $id ] && echo -e "\t\t\t\t\033[2;31m序号不能为空,请输入以下序号。\033[0m" && continue
      echo ""
      [[ ! $id =~ ^[0-9]+$ ]] && echo -e "\t\t\t\033[2;31m序号必须是[1-4]的整数" && continue
      echo ""
      if [ $id -eq 1 ];then
      	ssh $WEB01
      elif [ $id -eq 2 ];then
    	ssh $WEB02
      elif [ $id -eq 3 ];then
    	ssh $DB
      elif [ $id -eq 4 ];then
  	break
      elif [ $id = 219 ];then
	exit
      else 
	    echo -e "\t\t\t\033[2;31m请输入以下的正确序号！！！\033[0m"
	    echo ""
      fi
    done
  elif [ $num -eq 2 ];then
  	while true
  	do
  	    dev
  	    read -p "请选择你要连接的主机序号: " idd
	    [ -z $idd ] && echo -e "\t\t\t\033[2;31m序号不能为空,请输入以下序号\033[0m" && continue
	    echo ""
	    [[ ! $id =~ ^[0-9]$ ]] && echo -e "\t\t\t\033[2;31m序号必须是[1-9]的整数\033[0m" && continue
	    echo ""
   	    if [ $idd -eq 1 ];then
  	    	ssh $WEB01
  	    elif [ $idd -eq 2 ];then
  	    	break
  	    else
		echo -e "\t\t\t\033[2;31m请输入以下的正确序号！！！\033[0m"
		echo ""
  	    fi
          done
  else
	  echo -e "\t\t\t\033[2;31m请输入以下的正确序号！！！\033[0m"
	  echo ""
  fi
done
