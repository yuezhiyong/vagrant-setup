# 1.如何使用
1. 将vagrant-hadoop-cluster.Vagrantfile重新完整copy到一个单独的空文件夹下
2. 使用vagrant up命令启动整个集群节点
3. 修改该文件的node.vm.synced_folder ".", "/vagrant", disabled: true为node.vm.synced_folder ".", "/vagrant", type: 'rsync'
4. 再次执行vagrant reload命令,这样确保当前的文件夹下的data文件能够正确挂载到虚拟机的/vagrant目录下。


# 2. 将上述所有脚本放到对应目录
chmod +x /opt/sh/*/*.sh

# 4. 运行安装脚本
/opt/sh/utils/install-all.sh

日常使用

# 启动整个集群
/opt/sh/cluster/start-all.sh

# 停止整个集群
/opt/sh/cluster/stop-all.sh

# 查看集群状态
/opt/sh/cluster/status-all.sh

# 重启集群
/opt/sh/cluster/restart-all.sh

# 单独管理组件
/opt/sh/hadoop/hadoop-start.sh start      # 启动Hadoop
/opt/sh/kafka/kafka-manager.sh start      # 启动Kafka
/opt/sh/kafka/zk-start.sh start          # 启动Zookeeper
/opt/sh/flume/flume-manager.sh start      # 启动Flume

检查环境
# 检查集群环境
/opt/sh/utils/check-env.sh

# 同步配置
/opt/sh/utils/sync-config.sh