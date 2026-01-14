package org.example.flume.interceptor;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.reflect.TypeToken;
import org.apache.commons.collections.CollectionUtils;
import org.apache.flume.Context;
import org.apache.flume.Event;
import org.apache.flume.interceptor.Interceptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class JsonValidateInterceptor implements Interceptor {

    private static final Logger LOGGER = LoggerFactory.getLogger(JsonValidateInterceptor.class);

    @Override
    public void initialize() {

    }

    @Override
    public Event intercept(Event event) {
        Map<String, String> headers = event.getHeaders();
        String log = new String(event.getBody(), StandardCharsets.UTF_8);
        Pair<String, Boolean> headerPair = hasHeaderTs(log);
        if (headerPair.getSecond()) {
            String ts = headerPair.getFirst();
            headers.put("timestamp", ts);
        }
        return event;
    }

    private Pair<String, Boolean> hasHeaderTs(String body) {
        try {
            JsonObject jsonObject = new Gson().fromJson(body, new TypeToken<JsonObject>() {
            }.getType());
            JsonElement jsonElement = jsonObject.get("ts");
            String ts = jsonElement.getAsString();
            return new Pair<>(ts, true);
        } catch (Exception e) {
            LOGGER.error("无法正确处理当前Event:{}", body);
        }
        return new Pair<>(null, false);
    }


    @Override
    public List<Event> intercept(List<Event> list) {
        if (CollectionUtils.isEmpty(list)) {
            return new ArrayList<>();
        }
        List<Event> pass = new ArrayList<>();
        for (Event event : list) {
            String body = new String(event.getBody());
            Pair<String, Boolean> has = hasHeaderTs(body);
            if (!has.getSecond()) {
                LOGGER.warn("当前事件不准确:{}", body);
                continue;
            }
            pass.add(event);
        }
        return pass;
    }

    @Override
    public void close() {

    }


    /**
     * 关键在这里 ↓↓↓
     */
    public static class Builder implements Interceptor.Builder {

        @Override
        public Interceptor build() {
            return new JsonValidateInterceptor();
        }

        @Override
        public void configure(Context context) {
            // 读取 flume.conf 参数
        }
    }

}
