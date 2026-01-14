package org.example.datax.generator;


public class DataXCli {


    public static void main(String[] args) throws Exception {
        if (args.length < 5) {
            System.out.println("用法: java -jar datax-job-generator.jar <jdbcUrl> <user> <password> <dbName> [tableName] <outputDir>");
            System.out.println("示例:");
            System.out.println("  全库生成: java -jar datax-job-generator.jar jdbc:mysql://localhost:3306/ root 000000 gmall /datax-jobs");
            System.out.println("  单表生成: java -jar datax-job-generator.jar jdbc:mysql://localhost:3306/ root 000000 gmall orders /datax-jobs");
            System.exit(1);
        }

        String jdbcUrl = args[0];
        String user = args[1];
        String password = args[2];
        String dbName = args[3];
        String outputDir = null;
        String tableName = null;
        if(args.length > 5){
            tableName = args[4];
            outputDir = args[5];
        } else {
            outputDir = args[4];
        }
        DataXJobGenerator generator = new DataXJobGenerator(jdbcUrl, user, password, outputDir);
        generator.generate(dbName, tableName);
    }
}
