package org.example.flume.interceptor;

import org.apache.flume.conf.Configurable;
import org.apache.flume.conf.ConfigurableComponent;

public interface JsonInterceptorSerializer extends ConfigurableComponent, Configurable {
    String serialize(String value);
}
