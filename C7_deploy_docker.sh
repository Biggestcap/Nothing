# 安装一些必要的系统工具
yum install -y yum-utils device-mapper-persistent-data lvm2
# 添加软件源信息
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
# 添加源信息
sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
# 更新并安装Docker-CE
yum makecache fast
yum -y install docker-ce
# 开启Docker服务
service docker start
# 判断docker是否启动
if [ $? -eq 0 ]; then
    echo "docker start successful!"
else
    echo "failed!"
fi