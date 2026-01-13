package org.example.datax.generator;


public class DataXCli {


    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.out.println("用法: java -jar datax-job-generator.jar <jdbcUrl> <user> <password> <outputDir> [tableName]");
            System.out.println("示例:");
            System.out.println("  全库生成: java -jar datax-job-generator.jar jdbc:mysql://localhost:3306/gmall root 000000 /datax-jobs");
            System.out.println("  单表生成: java -jar datax-job-generator.jar jdbc:mysql://localhost:3306/gmall root 000000 /datax-jobs orders");
            System.exit(1);
        }

        String jdbcUrl = args[0];
        String user = args[1];
        String password = args[2];
        String dbName = args[3];
        String tableName = args.length > 5 ? args[4] : null;
        String outputDir = args.length > 5 ? args[5] : args[4];

        DataXJobGenerator generator = new DataXJobGenerator(jdbcUrl, user, password, outputDir);
        generator.generate(dbName, tableName);
    }
}
