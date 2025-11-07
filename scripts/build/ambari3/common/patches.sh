# 单点维护补丁清单（按顺序）
# 用绝对/相对路径都行，建议使用 repo 根为基准的相对路径
patch_files=(
  "/scripts/build/ambari3/common/patch2_0_0/patch0-ALL-IN-ONE.diff"
  "/scripts/build/ambari3/common/patch2_0_0/patch1-START-LOGBACK-LOGGER.diff"
  # 2.1.0
  "/scripts/build/ambari3/common/patch2_1_0/patch0-DEBIAN-BASE-SUP.diff"
  "/scripts/build/ambari3/common/patch2_1_0/patch1-DEBIAN-BASE-SUP.diff"
  "/scripts/build/ambari3/common/patch2_1_0/patch2-DEBIAN-DOLPHIN-RANGER-SUP.diff"
  "/scripts/build/ambari3/common/patch2_1_0/patch3-DEBIAN-FINAL-SUP.diff"
  # 2.2.0
  "/scripts/build/ambari3/common/patch2_2_0/patch0-KYLIN-BASE-SUP.diff"
  "/scripts/build/ambari3/common/patch2_2_0/patch1-KYLIN-ALL-COMPONENT-SUP.diff"
  # 2.2.1
  "/scripts/build/ambari3/common/patch2_2_1/patch0-KERBEROS-SUP-FIXED.diff"
  "/scripts/build/ambari3/common/patch2_2_1/patch1-ATLAS-RHEL-FIXED.diff"
  "/scripts/build/ambari3/common/patch2_2_1/patch2-VIEWS-COMPILE-FIXED.diff"
  "/scripts/build/ambari3/common/patch2_2_1/patch3-HUDI-PAIMON-BUGS-FIXED.diff"
  "/scripts/build/ambari3/common/patch2_2_1/patch4-KERBEROS-KAFKA-SOLR-HIVE-FIXED.diff"
)


