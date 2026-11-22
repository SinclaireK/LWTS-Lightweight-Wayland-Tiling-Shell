#!/bin/sh
# Weather from wttr.in (sends only your IP; pass a city to pin it): weather.sh [city]
# -> JSON {value: "8°C", sub: "Overcast", icon: <Phosphor name by the condition, night-aware>}
r=$(curl -fsm 8 "https://wttr.in/${1}?format=%t|%C|%S|%s&m" 2>/dev/null) || { echo '{"value":"--","sub":"offline"}'; exit; }
t=$(printf %s "$r" | cut -d'|' -f1 | sed 's/^+//'); c=$(printf %s "$r" | cut -d'|' -f2 | sed 's/ *$//')
rise=$(printf %s "$r" | cut -d'|' -f3 | cut -c1-5); set=$(printf %s "$r" | cut -d'|' -f4 | cut -c1-5); now=$(date +%H:%M)
night=0; { [ "$now" \< "$rise" ] || [ "$now" \> "$set" ]; } && night=1
l=$(printf %s "$c" | tr 'A-Z' 'a-z')
case "$l" in
  *thunder*) i=cloud-lightning ;;
  *snow*|*sleet*|*ice*|*blizzard*) i=cloud-snow ;;
  *rain*|*drizzle*|*shower*) i=cloud-rain ;;
  *fog*|*mist*|*haze*) i=cloud-fog ;;
  *partly*) [ $night = 1 ] && i=cloud-moon || i=cloud-sun ;;
  *cloud*|*overcast*) i=cloud ;;
  *) [ $night = 1 ] && i=moon || i=sun ;;
esac
printf '{"value":"%s","sub":"%s","icon":"%s"}\n' "$t" "$c" "$i"
