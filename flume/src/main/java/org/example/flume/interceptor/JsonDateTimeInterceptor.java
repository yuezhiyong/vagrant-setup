package org.example.flume.interceptor;

import com.google.common.base.Preconditions;
import org.apache.commons.lang.StringUtils;
import org.apache.flume.Context;
import org.apache.flume.conf.ComponentConfiguration;
import org.joda.time.DateTime;
import org.joda.time.format.DateTimeFormat;
import org.joda.time.format.DateTimeFormatter;


public class JsonDateTimeInterceptor implements JsonInterceptorSerializer {
    private DateTimeFormatter inputFormatter;
    private DateTimeFormatter outputFormatter;

    @Override
    public void configure(Context context) {
        String inputPattern = context.getString("inputPattern");
        String outputPattern = context.getString("outputPattern");
        Preconditions.checkArgument(!StringUtils.isEmpty(inputPattern),
                "Must configure with a valid inputPattern");
        Preconditions.checkArgument(!StringUtils.isEmpty(outputPattern),
                "Must configure with a valid outputPattern");
        inputFormatter = DateTimeFormat.forPattern(inputPattern);
        outputFormatter = DateTimeFormat.forPattern(outputPattern);
    }

    @Override
    public String serialize(String value) {
        DateTime dateTime = inputFormatter.parseDateTime(value);
        return outputFormatter.print(dateTime.getMillis());
    }

    @Override
    public void configure(ComponentConfiguration conf) {
    }
}
