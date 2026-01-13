package org.example.datax.generator;

import freemarker.template.Configuration;
import freemarker.template.Template;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.Writer;
import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class DataXJobGenerator {
    private final Configuration cfg;

    public DataXJobGenerator() throws IOException {
        cfg = new Configuration(Configuration.VERSION_2_3_32);
        cfg.setDefaultEncoding("UTF-8");
        cfg.setClassLoaderForTemplateLoading(
                Thread.currentThread().getContextClassLoader(),
                "template"
        );
    }

    /**
     * 查询数据库下所有表名
     */
    public List<String> getAllTables(String jdbcUrl, String username, String password, String dbName) throws SQLException {
        List<String> tables = new ArrayList<>();
        try (Connection conn = DriverManager.getConnection(jdbcUrl, username, password)) {
            DatabaseMetaData meta = conn.getMetaData();
            try (ResultSet rs = meta.getTables(dbName, null, "%", new String[]{"TABLE"})) {
                while (rs.next()) {
                    tables.add(rs.getString("TABLE_NAME"));
                }
            }
        }
        return tables;
    }

    /**
     * 生成 DataX Job 配置
     *
     * @param jdbcUrl      JDBC URL
     * @param mysqlUser    MySQL 用户
     * @param mysqlPassword MySQL 密码
     * @param dbName       数据库名
     * @param tableName    表名，如果为空则生成 db 下所有表
     * @param outputDir    输出目录
     */
    public void generate(String jdbcUrl, String mysqlUser, String mysqlPassword,
                         String dbName, String tableName, String outputDir) throws Exception {

        try (Connection conn = DriverManager.getConnection(jdbcUrl, mysqlUser, mysqlPassword)) {

            List<String> tables = new ArrayList<>();
            if (tableName == null || tableName.isEmpty()) {
                // 查询所有表
                DatabaseMetaData meta = conn.getMetaData();
                try (ResultSet rs = meta.getTables(dbName, null, "%", new String[]{"TABLE"})) {
                    while (rs.next()) {
                        tables.add(rs.getString("TABLE_NAME"));
                    }
                }
            } else {
                tables.add(tableName);
            }

            for (String table : tables) {
                List<String> columns = getColumns(conn, dbName, table);

                Map<String, Object> dataModel = new HashMap<>();
                dataModel.put("dbName", dbName);
                dataModel.put("tableName", table);
                dataModel.put("mysqlUser", mysqlUser);
                dataModel.put("mysqlPassword", mysqlPassword);
                dataModel.put("columns", columns);

                Template template = cfg.getTemplate("mysql-datax-job.ftl");

                File dir = new File(outputDir, dbName);
                if (!dir.exists()) dir.mkdirs();

                File outFile = new File(dir, table + ".json");
                try (Writer writer = new FileWriter(outFile)) {
                    template.process(dataModel, writer);
                }

                System.out.printf("生成成功: %s%n", outFile.getAbsolutePath());
            }
        }
    }

    /**
     * 获取表的列名
     */
    private List<String> getColumns(Connection conn, String dbName, String tableName) throws SQLException {
        List<String> columns = new ArrayList<>();
        DatabaseMetaData meta = conn.getMetaData();
        try (ResultSet rs = meta.getColumns(dbName, null, tableName, "%")) {
            while (rs.next()) {
                columns.add(rs.getString("COLUMN_NAME"));
            }
        }
        return columns;
    }
}
