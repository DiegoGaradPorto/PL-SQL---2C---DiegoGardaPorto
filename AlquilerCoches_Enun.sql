drop table modelos            cascade constraints;
drop table vehiculos        cascade constraints;
drop table clientes         cascade constraints;
drop table facturas       cascade constraints;
drop table lineas_factura     cascade constraints;
drop table reservas      cascade constraints;

drop sequence seq_modelos;
drop sequence seq_num_fact;
drop sequence seq_reservas;

create table clientes(
  NIF varchar(9) primary key,
  nombre  varchar(20) not null,
  ape1  varchar(20) not null,
  ape2  varchar(20) not null,
  direccion varchar(40) 
);


create sequence seq_modelos;

create table modelos(
  id_modelo     integer primary key,
  nombre      varchar(30) not null,
  precio_cada_dia   numeric(6,2) not null check (precio_cada_dia>=0));


create table vehiculos(
  matricula varchar(8)  primary key,
  id_modelo integer  not null references modelos,
  color   varchar(10)
);

create sequence seq_reservas;
create table reservas(
  idReserva integer primary key,
  cliente   varchar(9) references clientes,
  matricula varchar(8) references vehiculos,
  fecha_ini date not null,
  fecha_fin date,
  check (fecha_fin >= fecha_ini)
);

create sequence seq_num_fact;
create table facturas(
  nroFactura  integer primary key,
  importe   numeric( 8, 2),
  cliente   varchar(9) not null references clientes
);

create table lineas_factura(
  nroFactura  integer references facturas,
  concepto  char(60),
  importe   numeric( 7, 2),
  primary key ( nroFactura, concepto)
);

create or replace procedure alquilar_coche(arg_NIF_cliente varchar,
  arg_matricula varchar, arg_fecha_ini date, arg_fecha_fin date) is
  
  -- definimos las variables locales que vamos a utilizar en este procedimiento
    v_precio_cada_dia modelos.precio_cada_dia%type;
    v_nombre_modelo modelos.nombre%type;
    v_dias integer;
    v_importe_factura integer;
    v_comprobacion_reservas integer;
    
  -- definimos la excepcion para cliente inexistente
  cliente_inexistente EXCEPTION;
  PRAGMA EXCEPTION_INIT(cliente_inexistente, -2291);
    
begin
  -- 1: Comprobar que la fecha de inicio no es posterior a la fecha de fin
  if arg_fecha_ini > arg_fecha_fin then 
    raise_application_error(-20001, 'No pueden realizarse alquileres por períodos inferiores a 1 día.');
  end if; 
  
  -- 2: Obtener los datos del vehículo (modelo y precio) y verificar si existe
  begin 
    select m.precio_cada_dia, m.nombre
    into v_precio_cada_dia, v_nombre_modelo
    from vehiculos v
    join modelos m on v.id_modelo = m.id_modelo
    where v.matricula = arg_matricula
    for update;
  exception
    when no_data_found then
        raise_application_error(-20002, 'Vehículo inexistente.');
  end;
  
  -- 3: Verificar disponibilidad del coche para unas fechas determinadas
  select count(*)
  into v_comprobacion_reservas
  from reservas r
  where r.matricula = arg_matricula
  and (
    (arg_fecha_ini between r.fecha_ini and r.fecha_fin) or
    (arg_fecha_fin between r.fecha_ini and r.fecha_fin) or
    (arg_fecha_ini <= r.fecha_ini and arg_fecha_fin >= r.fecha_fin)
  );
  
  if v_comprobacion_reservas > 0 then 
    raise_application_error(-20003, 'El vehículo no está disponible para esas fechas.');
  end if;
  
  -- 4: Insertar reserva y verificar que existe el cliente
  begin 
    insert into reservas values (seq_reservas.nextval, arg_NIF_cliente, arg_matricula, arg_fecha_ini, arg_fecha_fin);
  exception
    when cliente_inexistente then 
        raise_application_error(-20004, 'Cliente inexistente');
  end;
  
  -- 5: Crear factura y línea de factura
  v_dias := arg_fecha_fin - arg_fecha_ini + 1;
  v_importe_factura := v_dias * v_precio_cada_dia;
  
  insert into facturas values (seq_num_fact.nextval, v_importe_factura, arg_NIF_cliente);
  
  insert into lineas_factura values (seq_num_fact.currval, v_dias || ' días alquilado el modelo ' || v_nombre_modelo, v_importe_factura);
  
  commit;
end;
/

create or replace
procedure reset_seq( p_seq_name varchar )
--From https://stackoverflow.com/questions/51470/how-do-i-reset-a-sequence-in-oracle
is
    l_val number;
begin
    --Averiguo cual es el siguiente valor y lo guardo en l_val
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    --Utilizo ese valor en negativo para poner la secuencia cero, pimero cambiando el incremento de la secuencia
    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || 
                                                          ' minvalue 0';
   --segundo pidiendo el siguiente valor
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    --restauro el incremento de la secuencia a 1
    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';

end;
/

create or replace procedure inicializa_test is
begin
  reset_seq( 'seq_modelos' );
  reset_seq( 'seq_num_fact' );
  reset_seq( 'seq_reservas' );
        
  
    delete from lineas_factura;
    delete from facturas;
    delete from reservas;
    delete from vehiculos;
    delete from modelos;
    delete from clientes;
   
    
    insert into clientes values ('12345678A', 'Pepe', 'Perez', 'Porras', 'C/Perezoso n1');
    insert into clientes values ('11111111B', 'Beatriz', 'Barbosa', 'Bernardez', 'C/Barriocanal n1');
    
    
    insert into modelos values ( seq_modelos.nextval, 'Renault Clio Gasolina', 15);
    insert into vehiculos values ( '1234-ABC', seq_modelos.currval, 'VERDE');

    insert into modelos values ( seq_modelos.nextval, 'Renault Clio Gasoil', 16);
    insert into vehiculos values ( '1111-ABC', seq_modelos.currval, 'VERDE');
    insert into vehiculos values ( '2222-ABC', seq_modelos.currval, 'GRIS');
  
    commit;
end;
/


exec inicializa_test;

create or replace procedure test_alquila_coches is
begin
  
  --caso 1 Todo correcto                                                                        
  begin
    inicializa_test; 
    -- Implementa aquí tu test
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-16', date '2024-06-20');
    dbms_output.put_line('Caso 1: Todo correcto');
  exception 
    when others then 
        dbms_output.put_line('Error : ' || sqlerrm);
  end;
	 
  --caso 2 nro dias negativo
  begin
    inicializa_test;
    -- Implementa aquí tu test
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-16', date '2024-06-10');
  exception 
    when others then
        if sqlcode = -20001 then 
            dbms_output.put_line('Caso 2: Error días negativos detectado correctamente. BIEN.' );
        else 
            dbms_output.put_line('Caso 2: Error días negativos no detectado. MAL.' || sqlerrm);
        end if;
  end;
  
  --caso 3 vehiculo inexistente
  begin
    inicializa_test;
    -- Implementa aquí tu test
    
    -- Inserción de una reserva de un vehículo inexistente 
    alquilar_coche('12345678A', '9999-ABC', date '2024-07-22', date '2024-07-24');
  exception 
    when others then 
        if sqlcode = -20002 then 
            dbms_output.put_line('Caso 3: Error vehículo inexistente detectado correctamente. BIEN.');
        else 
            dbms_output.put_line('Caso 3: Error vehículo inexistente no detectado. MAL.' || sqlerrm);
        end if;
  end;

  --caso 4 Intentar alquilar un coche ya alquilado
  --4.1 la fecha ini del alquiler esta dentro de una reserva
  begin
    inicializa_test;    
	-- Implementa aquí tu test
    
    -- Inserción una primera reserva correcta
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-16', date '2024-06-22');
    -- Inserción una segunda reserva que se solape con la primera teniendo su fecha de inicio dentro de la primera reserva.
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-18', date '2024-06-24');
  exception 
    when others then 
        if sqlcode = -20003 then 
            dbms_output.put_line('Caso 4.1: Error fecha inicio en una reserva detectado correctamente. BIEN.');
        else 
            dbms_output.put_line('Caso 4.1: Error fecha inicio en una reserva no detectado. MAL.' || sqlerrm);
        end if;
  end; 
  
   --4.2 la fecha fin del alquiler esta dentro de una reserva
  begin
    inicializa_test;    
	-- Implementa aquí tu test
    
    -- Inserción una primera reserva correcta
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-16', date '2024-06-22');
    -- Inserción de una segunda reserva solape con la primera, teniendo su fecha de fin dentro de la reserva  anterior
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-15', date '2024-06-18');
  exception 
    when others then 
        if sqlcode = -20003 then 
            dbms_output.put_line('Caso 4.2: Error fecha fin en una reserva detectado correctamente. BIEN.');
        else 
            dbms_output.put_line('Caso 4.2: Error fecha fin en una reserva no detectado. MAL.' || sqlerrm);
        end if;
  end; 
  
  --4.3 el intervalo del alquiler esta dentro de una reserva
  begin
    inicializa_test;    
	-- Implementa aquí tu test
    
    -- Inserción una primera reserva correcta
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-16', date '2024-06-22');
    -- Inserción de una segunda reserva solape con la primera, teniendo tanto su fecha de inicio como de fin dentro de la reserva  anterior
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-17', date '2024-06-18');  
  exception 
    when others then 
        if sqlcode = -20003 then 
            dbms_output.put_line('Caso 4.3: Error fecha inicio y fin en una reserva detectado correctamente. BIEN.');
        else 
            dbms_output.put_line('Caso 4.3: Error fecha inicio y  fin en una reserva no detectado. MAL.' || sqlerrm);
        end if;
  end; 
  
    --caso 5 cliente inexistente
  begin
    inicializa_test;
   -- Implementa aquí tu test
   alquilar_coche('99999999J', '1234-ABC', date '2024-10-18', date '2024-10-24');
  exception 
    when others then 
        if sqlcode = -20004 then 
            dbms_output.put_line('Caso 5: Error cliente inexistente detectado correctamente. BIEN.');
        else 
            dbms_output.put_line('Caso 5: Error cliente inexistente no detectado. MAL.' || sqlerrm);
        end if;
  end;
  
end;
/

set serveroutput on;
exec test_alquila_coches;

-- Llamamos al procedimiento alquilar_coche con diferentes tipos de reservas

-- CASO 1: Reservas correctas
begin
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-11', date '2024-06-14');
end;
/

begin
    alquilar_coche('11111111B', '1111-ABC', date '2024-06-11', date '2024-06-19');
end;
/

-- CASO 2: Reserva con duracion inferior a un día
begin 
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-14', date '2024-06-13');
end;
/

-- CASO 3: Reserva de un vehículo inexistente
begin 
    alquilar_coche('12345678A', '9999-ABC', date '2024-06-16', date '2024-06-17');
end;
/

-- CASO 4: Reservas solapadas
-- CASO 4.1: Fecha de inicio dentro de otra reserva
begin 
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-12', date '2024-06-15');
end;
/
--CASO 4.2: Feha de fin dentro  reserva
begin 
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-10', date '2024-06-13');
end;
/

-- CASO 4.3: Fecha de inicio y de fin dentro de otra reserva
begin 
    alquilar_coche('12345678A', '1234-ABC', date '2024-06-12', date '2024-06-13');
end;
/

-- CASO 5: Reserva de un cliente inexistente
begin 
    alquilar_coche('99999999X', '1234-ABC', date '2024-07-12', date '2024-07-13');
end;
/


-- Hacemos uso de SELECTS para ver el contenido de las tablas y el resultado de las operaciones
select *  from clientes; 
select *  from modelos; 
select *  from vehiculos; 
select *  from reservas; 
select *  from facturas; 
select *  from lineas_factura;

-- APARTADO 6 - PREGUNTAS
-- P5a
/*
Ese proceso de bloqueo del vehículo se hace evitar que errores en la base de datos, impidiendo que otros usuarios hagan modificaciones. 

Al bloquear dicho vehículo se impide que otro usuario haga una reserva del mismo ni realive ninguna modificación
hasta que acabe esta transacción. 

Una vez acabe la transacción se libera el bloqueo y dicho vehículo ya puede ser reservado por otra transacción.

*/

--P5b
/*
En el paso 4 se ejecuta un INSERT de una reserva en la tabla reservas con los datos del cliente, el vehículo
y las fechas de inicio y de final del alquiler.

Este INSERT sigue siendo válido para el paso 5, pues los datos de esa reserva son utilizados para crear 
una factura en la tabla facturas con los datos del NIF del cliente, el vehículo y el número de días de la reserva. 

Además también se creará una línea de facturacon los datos del nroFactura, el concepto y el importe (precio total del alquiler).

*/

--P5c
/*
No, porque cuando se ejecuta de manera concurrente el método ALQUILAR_COCHE ya sea con los mismos valores o con diferentes
se estudian los datos de estas reservas para ver si existen tanto el vehículo como el cliente y para ver si se solapan las reservas. 

Estas reservas se estudian entre otros pasos, en el paso 4, por lo que si se llegan a añadir a la base de datos, serán las mismas 
de las que se recogen en el SELECT. 

Las reservas incompatibles se verían al realizar el estudio de los datos y no se añadirían, dando lugar a las correspondientes excepciones 
en cada momento. 

Por ejemplo si ejecutamos el procedimiento AQLUILAR_COCHE dos veces con los mismos datos, el sistema se daría cuenta de la incopatibilidad, 
añadiría la primera reserva a la base de datos pero a la hora de intentar añadir la segunda se mostraría el mensaje de error de que dicho
vehículo no está disponible para esas fechas (pues se solaparían).
*/

--P5d
/*
La estrategia de programación que he utilizado en este código ha sido una estrategia defensiva.

Esto se puede ver en el código en que he realizado primero comprobaciones y verificaciones y posteriormente
he llevado a cabo las operaciones. 

Por ejemplo, primero he verificado si existe un vehículo. Si es así se ejecutan las acciones necesarias, 
en caso contrario salta la excepción correspondiente.

*/

