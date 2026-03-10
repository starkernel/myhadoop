# Flink 构建修复脚本
echo '→ 应用 Flink 构建修复...'

cat > /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build << 'EOFSCRIPT'
set -ex
export PATH=/opt/modules/apache-maven-3.8.4/bin:/usr/local/bin:/usr/bin:/bin:$PATH
echo '→ 修复 Flink POM 文件...'
[ -f 'flink-clients/pom.xml' ] && sed -i 's|<phase>process-test-classes</phase>|<phase>none</phase>|g' flink-clients/pom.xml && echo '✓ flink-clients 已修复'
[ -f 'flink-python/pom.xml' ] && sed -i '/<id>build-test-jars<\/id>/,/<\/execution>/ s|<phase>package</phase>|<phase>none</phase>|' flink-python/pom.xml && echo '✓ flink-python 已修复'
echo '✓ POM 修复完成'
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true -Dskip.npm=true"
. `dirname $0`/bigtop.bom
[ $HOSTTYPE = 'powerpc64le' ] && sed -i 's|<nodeVersion>v10.9.0</nodeVersion>|<nodeVersion>v12.22.1</nodeVersion>|' flink-runtime-web/pom.xml
git_path="$(cd $(dirname $0)/../../../.. && pwd)"
cmd_from="cd ../.. && husky install flink-runtime-web/web-dashboard/.husky"
repl_from=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_from")
if [[ "$0" == *rpm* ]]; then
  package_json_path="build/flink/rpm/BUILD/flink-$FLINK_VERSION/flink-runtime-web/web-dashboard"
  cmd_to="cd $git_path && husky install $package_json_path/.husky"
  repl_to=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_to")
elif [[ "$0" == *debian* ]]; then
  package_json_path="output/flink/flink-$FLINK_VERSION/flink-runtime-web/web-dashboard"
  cmd_to="cd $git_path && husky install $package_json_path/.husky"
  repl_to=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_to")
fi
sed -i "s/$repl_from/$repl_to/" flink-runtime-web/web-dashboard/package.json
mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -Dmaven.test.skip=true -Dhadoop.version=$HADOOP_VERSION "$@"
cd flink-dist
mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -Dmaven.test.skip=true -Dhadoop.version=$HADOOP_VERSION "$@"
EOFSCRIPT

chmod +x /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build
echo '✓ Flink 修复已应用'
