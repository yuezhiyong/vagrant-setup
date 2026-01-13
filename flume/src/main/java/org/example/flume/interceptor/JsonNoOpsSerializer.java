package org.example.flume.interceptor;

import org.apache.flume.Context;
import org.apache.flume.conf.ComponentConfiguration;

public class JsonNoOpsSerializer implements JsonInterceptorSerializer {
    @Override
    public String serialize(String value) {
        return value;
    }

    @Override
    public void configure(Context context) {

    }

    @Override
    public void configure(ComponentConfiguration componentConfiguration) {

    }
}
