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
      "defaultFS": "hdfs://centos-201:9000",
      "fileType": "orc",
      "path": "/original_data/${mysqlDatabase}/${tableName}",
      "fileName": "${tableName}",
      "column": [
      <#list columns as c>
        {
          "name": "${c.name}",
          "type": "${c.type}"
        }<#if c_has_next>,</#if>
      </#list>
      ],
      "writeMode": "append"
    }
  }
}
