package org.example.datax.generator.model;

public class ColumnMeta {
    private final String name;
    private final String type;

    public ColumnMeta(String name, String type) {
        this.name = name;
        this.type = type;
    }

    public String getName() { return name; }
    public String getType() { return type; }
}
