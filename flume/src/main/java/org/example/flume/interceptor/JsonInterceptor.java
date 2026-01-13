package org.example.flume.interceptor;

import com.google.common.base.Charsets;
import com.google.common.base.Preconditions;
import com.google.common.base.Throwables;
import com.nebhale.jsonpath.JsonPath;
import org.apache.commons.lang.StringUtils;
import org.apache.flume.Context;
import org.apache.flume.Event;
import org.apache.flume.interceptor.Interceptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.example.flume.interceptor.JsonInterceptor.Constants.*;

public class JsonInterceptor implements Interceptor {

    private static final Logger logger = LoggerFactory.getLogger(JsonInterceptor.class);

    private final String headerName;
    private final String headerJSONPath;
    private final JsonInterceptorSerializer serializer;

    public JsonInterceptor(String headerName, String headerJSONPath, JsonInterceptorSerializer serializer) {
        this.headerName = headerName;
        this.headerJSONPath = headerJSONPath;
        this.serializer = serializer;
    }

    @Override
    public void initialize() {
    }

    @Override
    public Event intercept(Event event) {
        try {

            String body = new String(event.getBody(), Charsets.UTF_8);

            Map<String, String> headers = event.getHeaders();
            //String value = JsonPath.read(body, headerJSONPath);
            JsonPath namePath = JsonPath.compile(headerJSONPath);
            String value = namePath.read(body, String.class);
            if (value != null) {
                headers.put(headerName, serializer.serialize(value));
            }
        } catch (java.lang.ClassCastException e) {
            logger.error("Skipping event due to: ClassCastException.", e);
        } catch (Exception e) {
            logger.warn("Skipping event due to: unknown error.", e);
            e.printStackTrace();
        }
        return event;
    }

    @Override
    public List<Event> intercept(List<Event> events) {

        List<Event> interceptedEvents = new ArrayList<>(events.size());
        for (Event event : events) {
            Event interceptedEvent = intercept(event);
            interceptedEvents.add(interceptedEvent);
        }

        return interceptedEvents;
    }

    @Override
    public void close() {
    }

    public static class Builder implements Interceptor.Builder {

        private String headerName;
        private String headerJSONPath;
        private JsonInterceptorSerializer serializer;
        private final JsonInterceptorSerializer defaultSerializer = new JsonNoOpsSerializer();

        @Override
        public void configure(Context context) {
            headerName = context.getString(CONFIG_HEADER_NAME);
            headerJSONPath = context.getString(CONFIG_HEADER_JSONPATH);

            configureSerializers(context);
        }

        @Override
        public JsonInterceptor build() {
            Preconditions.checkArgument(headerName != null, "Header name was misconfigured");
            Preconditions.checkArgument(headerJSONPath != null, "Header JSONPath was misconfigured");
            return new JsonInterceptor(headerName, headerJSONPath, serializer);
        }

        private void configureSerializers(Context context) {
            String serializerListStr = context.getString(CONFIG_SERIALIZERS);
            if (StringUtils.isEmpty(serializerListStr)) {
                serializer = defaultSerializer;
                return;
            }

            String[] serializerNames = serializerListStr.split("\\s+");
            if (serializerNames.length > 1) {
                logger.warn("Only one serializer is supported.");
            }
            String serializerName = serializerNames[0];

            Context serializerContexts = new Context(context.getSubProperties(CONFIG_SERIALIZERS + "."));
            Context serializerContext = new Context(serializerContexts.getSubProperties(serializerName + "."));

            String type = serializerContext.getString(CONFIG_SERIALIZER_TYPE, DEFAULT_SERIALIZER);
            String name = serializerContext.getString(CONFIG_SERIALIZER_NAME);

            Preconditions.checkArgument(!StringUtils.isEmpty(name), "Supplied name cannot be empty.");
            if (DEFAULT_SERIALIZER.equals(type)) {
                serializer = defaultSerializer;
            } else {
                serializer = getCustomSerializer(type, serializerContext);
            }

        }

        private JsonInterceptorSerializer getCustomSerializer(String clazzName, Context context) {
            try {
                JsonInterceptorSerializer serializer = (JsonInterceptorSerializer) Class.forName(clazzName).newInstance();
                serializer.configure(context);
                return serializer;
            } catch (Exception e) {
                logger.error("Could not instantiate event serializer.", e);
                Throwables.propagate(e);
            }
            return defaultSerializer;
        }
    }


    public static class Constants {

        public static final String CONFIG_SERIALIZERS = "serializers";
        public static final String DEFAULT_SERIALIZER = "DEFAULT";
        public static final String CONFIG_HEADER_NAME = "name";
        public static final String CONFIG_HEADER_JSONPATH = "jsonpath";
        public static final String CONFIG_SERIALIZER_TYPE = "type";
        public static final String CONFIG_SERIALIZER_NAME = "name";
    }
}
