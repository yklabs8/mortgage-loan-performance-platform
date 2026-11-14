-- The warehouse can read user events but cannot update OLTP events; a zero-row UPDATE only checks the privilege and changes no data.
declare
   l_rows number;
   l_denied boolean := false;
begin
   select count(*) into l_rows
   from loan_oltp.user_change_event;

   begin
      execute immediate
         'update loan_oltp.user_change_event '
         || 'set loaded_at = loaded_at where 1 = 0';
      exception
         when others then
            if sqlcode in (-1031, -41900) then
               l_denied := true;
            else
               raise;
            end if;
   end;
   if not l_denied then
      raise_application_error(-20161, 'The warehouse can still update OLTP user events');
   end if;
   dbms_output.put_line('The warehouse can read events but cannot update OLTP events');
end;
/
