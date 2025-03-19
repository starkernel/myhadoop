# Ambari+Bigtop 一站式编译和部署解决方案 🚀✨

<p align="center">
  <a href="https://gitee.com/tt-bigdata/ambari-env">
    <img src="https://img.shields.io/badge/dynamic/json?color=red&label=Gitee%20Stars&query=%24.stargazers_count&suffix=%20stars&url=https%3A%2F%2Fgitee.com%2Fapi%2Fv5%2Frepos%2Ftt-bigdata%2Fambari-env" alt="Gitee Stars">
  </a>
  <a href="https://opensource.org/licenses/Apache-2.0">
    <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="Apache 2.0 License">
  </a>
  <br>
  <img src="https://img.shields.io/badge/Ambari-2.8.0-orange" alt="Ambari 2.8.0">
  <img src="https://img.shields.io/badge/Bigtop-3.2.0-green" alt="Bigtop 3.2.0">
</p>


---

## 📚 项目简介

本项目基于以下版本进行魔改与增强，提供一站式编译、部署、管理解决方案：

- **Ambari 2.8.0**
- **Bigtop 3.2.0**

提供 **开箱即用** 的大数据组件部署方案，简化运维，支持多种主流组件，致力于打造稳定、可靠、高效的大数据生态环境。

---

## 🚀 版本说明

| **版本**     | **组件名称**         | **组件版本**   | **env 版本** | **支持时间**           |
|------------|------------------|------------|------------|--------------------|
| **v1.0.5** | Ozone            | 1.4.1      | 1.0.5      | ✅ 2025/02 (已支持)    |
|            | Impala           | 4.4.1      | 1.0.5      | ✅ 2025/02 (已支持)    |
|            | Nightingale      | 7.7.2      | 1.0.5      | ✅ 2025/01 (已支持)    |
|            | Categraf         | 0.4.1      | 1.0.5      | ✅ 2025/01 (已支持)    |
|            | VictoriaMetrics  | 1.109.1    | 1.0.5      | ✅ 2025/01 (已支持)    |
|            | Cloudbeaver      | 24.3.3     | 1.0.5      | ✅ 2025/01 (已支持)    |
|            | Celeborn         | 0.5.3      | 1.0.5      | ✅ 2025/01 (已支持)    |
| **v1.0.4** | Doris            | 2.1.7      | 1.0.4      | ✅ 2025/01 (已支持)    |
| **v1.0.3** | Phoenix          | 5.1.2      | 1.0.3      | ✅ 2024/10/15 (已支持) |
|            | Dolphinscheduler | 3.2.2      | 1.0.3      | ✅ 2024/10/15 (已支持) |
| **v1.0.2** | Redis            | 7.4.0      | 1.0.2      | ✅ 2024/09/10 (已支持) |
| **v1.0.1** | Sqoop            | 1.4.7      | 1.0.1      | ✅ 2024/08/15 (已支持) |
|            | Ranger           | 2.4.0      | 1.0.1      | ✅ 2024/08/15 (已支持) |
| **v1.0.0** | Zookeeper        | 3.5.9      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Hadoop           | 3.3.4      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Flink            | 1.15.3     | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | HBase            | 2.4.13     | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Hive             | 3.1.3      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Kafka            | 2.8.1      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Spark            | 3.2.3      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Solr             | 8.11.2     | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Tez              | 0.10.1     | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Zeppelin         | 0.10.1     | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Livy             | 0.7.1      | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Ambari           | branch-2.8 | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Ambari Metrics   | branch-3.0 | 1.0.0      | ✅ 2024/08/01 (已支持) |
|            | Ambari Infra     | master     | 1.0.0      | ✅ 2024/08/01 (已支持) |

---

## 🔧 快速上手

```bash
# clone 项目后

# 执行
docker-compose -f docker-compose.yml up -d

# 开始编译
bash /scripts/build/onekey_build.sh

```

## 效果图

![img.png](.docs/img_66.png)
![img.png](.docs/img_15.png)

---

## ❤️ 支持本项目

如果你觉得本项目对你有帮助，可以通过以下方式支持：

1. ⭐ **Star** 本项目，帮助它被更多人看到 🚀
2. 📢 **分享** 本项目，帮助更多开发者受益
3. 🍵 **打赏**，请作者喝一杯茶 ☕（见下方二维码）

|                        微信赞赏                        |                           微信                           |                        QQ 群                        |                
|:--------------------------------------------------:|:------------------------------------------------------:|:--------------------------------------------------:|
| <img  src='.docs/img_22.png' style="zoom: 33%;" /> | <img src='.docs/img_23.png' alt="WeChat QR" width=150> | <img src='.docs/img_24.png' alt="QQ QR" width=150> |

---

## 📜 许可证

本项目采用 [Apache 2.0](LICENSE) 许可证。

---
