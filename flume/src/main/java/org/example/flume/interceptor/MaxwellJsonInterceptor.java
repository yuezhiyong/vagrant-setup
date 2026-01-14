package org.example.flume.interceptor;

import com.google.common.base.Charsets;
import com.google.common.base.Splitter;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import lombok.extern.slf4j.Slf4j;
import org.apache.flume.Context;
import org.apache.flume.Event;
import org.apache.flume.interceptor.Interceptor;

import java.lang.reflect.Type;
import java.util.*;

@Slf4j
public class MaxwellJsonInterceptor implements Interceptor {
    private static final Type mapType = new TypeToken<Map<String, Object>>() {
    }.getType();

    private static final Gson gson = new Gson();

    private final boolean preserveExisting;
    private final boolean insertHeader;
    private final Set<String> headerKeys;

    public MaxwellJsonInterceptor(boolean preserveExisting, boolean insertHeader, Set<String> headerKeys) {
        this.preserveExisting = preserveExisting;
        this.insertHeader = insertHeader;
        this.headerKeys = headerKeys;
    }


    @Override
    public void initialize() {

    }

    @Override
    public Event intercept(Event event) {
        if (event == null) {
            return null;
        }

        Map<String, String> headers = event.getHeaders();
        String body = new String(event.getBody(), Charsets.UTF_8);

        Map<String, Object> jsonMap;

        try {
            jsonMap = gson.fromJson(body, mapType);
        } catch (Exception e) {
            // JSON 解析失败，丢弃 event
            log.error("解析Event格式失败:{}", body, e);
            return null;
        }

        if (jsonMap == null) {
            return null;
        }

        for (Map.Entry<String, Object> entry : jsonMap.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();

            if (value == null) {
                continue;
            }

            // preserveExisting = true 时，不覆盖已有 header
            if (preserveExisting && headers.containsKey(key)) {
                continue;
            }

            if (insertHeader && !headerKeys.contains(key)) {
                headers.put(key, value.toString());
            }
        }
        return event;
    }

    @Override
    public List<Event> intercept(List<Event> list) {
        Iterator<Event> it = list.iterator();
        while (it.hasNext()) {
            Event event = intercept(it.next());
            if (event == null) {
                it.remove();
            }
        }
        return list;
    }

    @Override
    public void close() {

    }

    public static class Builder implements Interceptor.Builder {

        private boolean preserveExisting = true;
        private boolean insertHeader = true;

        private Set<String> headerKeys;

        @Override
        public void configure(Context context) {
            preserveExisting = context.getBoolean("preserveExisting", true);
            insertHeader = context.getBoolean("insertHeader", true);
            headerKeys = wrapperHeaderKeys(context.getString("headerKeys"));
        }


        private Set<String> wrapperHeaderKeys(String headerKeys) {
            Set<String> res = new HashSet<>();
            Splitter.on(",").split(headerKeys).forEach(res::add);
            return res;
        }

        @Override
        public Interceptor build() {
            return new MaxwellJsonInterceptor(preserveExisting, insertHeader, headerKeys);
        }
    }


}
