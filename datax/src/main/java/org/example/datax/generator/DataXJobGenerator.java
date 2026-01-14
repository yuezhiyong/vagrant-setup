package org.example.datax.generator;

import freemarker.template.Configuration;
import freemarker.template.Template;
import freemarker.template.TemplateExceptionHandler;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class DataXJobGenerator {
    private final String jdbcUrl;
    private final String user;
    private final String password;
    private final String outputDir;

    private final Configuration cfg;

    public DataXJobGenerator(String jdbcUrl, String user, String password, String outputDir) throws IOException {
        this.jdbcUrl = jdbcUrl;
        this.user = user;
        this.password = password;
        this.outputDir = outputDir;

        // 初始化 Freemarker
        cfg = new Configuration(Configuration.VERSION_2_3_31);
        cfg.setClassLoaderForTemplateLoading(this.getClass().getClassLoader(), "/template");
        cfg.setDefaultEncoding("UTF-8");
        cfg.setTemplateExceptionHandler(TemplateExceptionHandler.RETHROW_HANDLER);
        cfg.setLogTemplateExceptions(false);
        cfg.setWrapUncheckedExceptions(true);
    }

    /**
     * MySQL -> DataX/HDFS 类型映射
     */
    private String mapMySQLTypeToDataX(String mysqlType) {
        if (mysqlType == null) return "string";
        mysqlType = mysqlType.toLowerCase();
        if (mysqlType.contains("char") || mysqlType.contains("text")) return "string";
        if (mysqlType.matches("tinyint|smallint|int|mediumint")) return "int";
        if (mysqlType.equals("bigint")) return "bigint";
        if (mysqlType.equals("float") || mysqlType.equals("double")) return "double";
        if (mysqlType.contains("decimal") || mysqlType.contains("numeric")) return "decimal";
        if (mysqlType.equals("date")) return "date";
        if (mysqlType.contains("timestamp")) return "timestamp";
        if (mysqlType.equals("bit")) return "boolean";
        return "string";
    }

    /**
     * 查询数据库所有表
     */
    private List<String> listTables(String dbName, Connection conn) throws SQLException {
        List<String> tables = new ArrayList<>();
        DatabaseMetaData metaData = conn.getMetaData();
        try (ResultSet rs = metaData.getTables(dbName, null, "%", new String[]{"TABLE"})) {
            while (rs.next()) {
                tables.add(rs.getString("TABLE_NAME"));
            }
        }
        return tables;
    }

    /**
     * 查询表的列信息
     */
    private List<Map<String, String>> getColumns(String dbName, String tableName, Connection conn) throws SQLException {
        List<Map<String, String>> columns = new ArrayList<>();
        DatabaseMetaData metaData = conn.getMetaData();
        try (ResultSet rs = metaData.getColumns(dbName, null, tableName, "%")) {
            while (rs.next()) {
                String colName = rs.getString("COLUMN_NAME");
                String colType = rs.getString("TYPE_NAME");
                Map<String, String> columnMap = new HashMap<>();
                columnMap.put("name", colName);
                columnMap.put("type", mapMySQLTypeToDataX(colType));
                columns.add(columnMap);
            }
        }
        return columns;
    }

    /**
     * 生成 DataX JSON 文件
     */
    private void generateJob(String dbName, String tableName, List<Map<String, String>> columns) throws Exception {
        Template template = cfg.getTemplate("mysql-datax-job.ftl");

        Map<String, Object> data = new HashMap<>();
        data.put("mysqlUser", user);
        data.put("mysqlPassword", password);
        data.put("mysqlDatabase", dbName);
        data.put("tableName", tableName);
        data.put("columns", columns);

        // 确保输出目录存在
        String safeTableName = (tableName == null || tableName.isEmpty()) ? "all_tables" : tableName;
        File outFile = new File(outputDir, dbName + "." + safeTableName + ".json");

        // 确保父目录存在
        if (!outFile.getParentFile().exists()) {
            outFile.getParentFile().mkdirs();
        }

        try (Writer writer = new OutputStreamWriter(Files.newOutputStream(outFile.toPath()), StandardCharsets.UTF_8)) {
            template.process(data, writer);
        }

        System.out.println("Generated dataX job file at: " + outFile.getAbsolutePath());
    }

    /**
     * 主方法：支持 db 或 db+table
     */
    public void generate(String dbName, String tableName) throws Exception {
        try (Connection conn = DriverManager.getConnection(jdbcUrl, user, password)) {
            // 检查数据库是否存在
            List<String> databases = new ArrayList<>();
            try (ResultSet rs = conn.getMetaData().getCatalogs()) {
                while (rs.next()) {
                    databases.add(rs.getString("TABLE_CAT"));
                }
            }
            if (!databases.contains(dbName)) {
                throw new SQLException("Database does not exist: " + dbName);
            }

            if (tableName == null || tableName.isEmpty()) {
                // 全库生成
                List<String> tables = listTables(dbName, conn);
                if (tables.isEmpty()) {
                    throw new SQLException("Database " + dbName + " has no tables.");
                }
                for (String t : tables) {
                    List<Map<String, String>> cols = getColumns(dbName, t, conn);
                    generateJob(dbName, t, cols);
                }
            } else {
                // 单表生成，先检查表是否存在
                List<String> tables = listTables(dbName, conn);
                if (!tables.contains(tableName)) {
                    throw new SQLException("Table does not exist: " + tableName);
                }
                List<Map<String, String>> cols = getColumns(dbName, tableName, conn);
                generateJob(dbName, tableName, cols);
            }
        }
    }

}
