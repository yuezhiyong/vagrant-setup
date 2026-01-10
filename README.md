初始化安装

# 1. 创建目录结构
mkdir -p /opt/sh/{common,hadoop,kafka,flume,cluster,utils}
mkdir -p /opt/module

# 2. 将上述所有脚本放到对应目录
# 3. 设置权限
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