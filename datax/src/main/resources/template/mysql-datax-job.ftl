{
  "job": {
    "setting": {
      "speed": {
        "channel": "3"
      }
    },
    "content": [
      {
        "reader": {
          "name": "mysqlreader",
          "parameter": {
            "username": "${mysqlUser}",
            "password": "${mysqlPassword}",
            "column": [<#list columns as c>"${c}"<#if c_has_next>,</#if></#list>],
            "table": ["${tableName}"],
            "connection": [
              {
                "jdbcUrl": ["${dbName}"]
              }
            ]
          }
        },
        "writer": {
          "name": "hdfswriter",
          "parameter": {
            "defaultFS": "hdfs://namenode:9000",
            "fileType": "orc",
            "path": "/data/${dbName}/${tableName}/",
            "fileName": "${tableName}",
            "column": [<#list columns as c>"${c}"<#if c_has_next>,</#if></#list>]
          }
        }
      }
    ]
  }
}