package org.example.datax.generator.model;

import java.util.List;

public class TableMeta {
    private final String tableName;
    private final List<ColumnMeta> columns;

    public TableMeta(String tableName, List<ColumnMeta> columns) {
        this.tableName = tableName;
        this.columns = columns;
    }

    public String getTableName() { return tableName; }
    public List<ColumnMeta> getColumns() { return columns; }
}
