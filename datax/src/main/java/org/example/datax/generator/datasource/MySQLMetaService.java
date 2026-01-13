package org.example.datax.generator.datasource;

import org.example.datax.generator.model.ColumnMeta;
import org.example.datax.generator.model.TableMeta;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class MySQLMetaService {
    private final String url;
    private final String user;
    private final String password;

    public MySQLMetaService(String url, String user, String password) {
        this.url = url;
        this.user = user;
        this.password = password;
    }

    public TableMeta loadTable(String db, String table) throws Exception {
        List<ColumnMeta> columns = new ArrayList<>();

        try (Connection conn = DriverManager.getConnection(url, user, password)) {
            String sql = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS " +
                    "WHERE TABLE_SCHEMA=? AND TABLE_NAME=? ORDER BY ORDINAL_POSITION";

            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, db);
                ps.setString(2, table);

                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    columns.add(new ColumnMeta(
                            rs.getString("COLUMN_NAME"),
                            rs.getString("DATA_TYPE")
                    ));
                }
            }
        }
        return new TableMeta(table, columns);
    }
}
