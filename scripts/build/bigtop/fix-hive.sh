echo '→ 应用 Hive do-component-build 修复...'

DO_BUILD='/opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build'

if [ -f "$DO_BUILD" ]; then
    # 在 set -ex 后、bigtop.bom 前插入修复代码
    sed -i '/^set -ex$/a\
\
# === Hive Log4j 兼容性修复 ===\
echo "→ 修复 Hive Log4j 兼容性问题..."\
QUERY_TRACKER="llap-server/src/java/org/apache/hadoop/hive/llap/daemon/impl/QueryTracker.java"\
if [ -f "$QUERY_TRACKER" ]; then\
    sed -i "s/import org.apache.logging.slf4j.Log4jMarker;/import org.slf4j.Marker;/" "$QUERY_TRACKER"\
    sed -i "s/Log4jMarker/Marker/g" "$QUERY_TRACKER"\
    echo "✓ QueryTracker.java 已修复"\
else\
    echo "⚠ QueryTracker.java 不存在，跳过修复"\
fi\
echo "✓ Hive 修复完成"\
' "$DO_BUILD"
    
    echo '✓ Hive do-component-build 已修复'
else
    echo '⚠ do-component-build 不存在'
fi
