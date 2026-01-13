package org.example.datax.generator;


import java.util.List;

public class DataXCli {


    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.out.println("用法: java -jar datax-generator.jar <jdbcUrl> <user> <password> <dbName> [tableName] <outputDir>");
            System.exit(1);
        }

        String jdbcUrl = args[0];
        String user = args[1];
        String password = args[2];
        String dbName = args[3];
        String tableName = null;
        String outputDir;

        if (args.length == 5) {
            outputDir = args[4];
        } else if (args.length == 6) {
            tableName = args[4];
            outputDir = args[5];
        } else {
            System.out.println("参数错误！");
            System.exit(1);
            return;
        }

        DataXJobGenerator generator = new DataXJobGenerator();

        if (tableName != null && !tableName.isEmpty()) {
            // 只生成指定表
            generator.generate(jdbcUrl, user, password, dbName, tableName, outputDir);
        } else {
            // 生成数据库下所有表
            List<String> tables = generator.getAllTables(jdbcUrl, user, password, dbName);
            if (tables.isEmpty()) {
                System.out.println("数据库下没有找到表！");
                System.exit(1);
            }
            for (String table : tables) {
                generator.generate(jdbcUrl, user, password, dbName, table, outputDir);
            }
        }

        System.out.println("全部生成完成!");
    }
}
