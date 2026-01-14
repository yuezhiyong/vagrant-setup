{
    "job":
    {
        "setting":
        {
            "speed":
            {
                "channel": 5
            },
            "errorLimit":
            {
                "record": 1000,
                "percentage": 0.05
            }
        },
        "content":
        [
            {
              "reader": {
                "name": "mysqlreader",
                "parameter": {
                  "username": "${mysqlUser}",
                  "password": "${mysqlPassword}",
                  "column": [
                  <#list columns as c>
                    "${c.name}"<#if c_has_next>,</#if>
                  </#list>
                  ],
                  "splitPk": "id",
                  "connection": [
                    {
                      "table": ["${tableName}"],
                      "jdbcUrl": ["jdbc:mysql://localhost:3306/${mysqlDatabase}"]
                    }
                  ]
                }
              },
              "writer": {
                "name": "hdfswriter",
                "parameter": {
                  "defaultFS": "hdfs://centos-101:9000",
                  "fileType": "orc",
                  "path": "/original_data/db/${mysqlDatabase}/${tableName}_full/{date}",
                  "fileName": "${tableName}",
                  "column": [
                  <#list columns as c>
                    {
                      "name": "${c.name}",
                      "type": "${c.type}"
                    }<#if c_has_next>,</#if>
                  </#list>
                  ],
                  "writeMode": "nonConflict",
                  "fieldDelimiter": "\t",
                  "compress": "SNAPPY",
                  "encoding": "UTF-8"
                }
              }
            }
        ]
    }
}