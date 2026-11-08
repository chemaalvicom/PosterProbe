#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Utilidades Objective-C: capturar excepciones (Swift no puede), introspección del
/// runtime y registro de cierres (excepciones no capturadas y señales).
@interface ObjCCatch : NSObject
/// Ejecuta un bloque. Devuelve nil si fue bien, o la descripción de la excepción.
+ (nullable NSString *)run:(NS_NOESCAPE void (^)(void))block NS_SWIFT_NAME(run(_:));
/// value(forKey:) protegido: devuelve el valor o nil, y el error en `error`.
+ (nullable id)valueOf:(id)object forKey:(NSString *)key error:(NSString * _Nullable * _Nullable)error NS_SWIFT_NAME(value(of:forKey:error:));
/// Todas las propiedades declaradas (clase y superclases hasta NSObject).
+ (NSArray<NSString *> *)propertyNamesOfClass:(Class)cls NS_SWIFT_NAME(propertyNames(of:));
/// Solo propiedades seguras para KVC: objetos no weak, escalares y structs CG.
+ (NSArray<NSString *> *)safePropertyNamesOfClass:(Class)cls NS_SWIFT_NAME(safePropertyNames(of:));
/// Métodos de instancia sin argumentos (posibles getters).
+ (NSArray<NSString *> *)getterNamesOfClass:(Class)cls NS_SWIFT_NAME(getterNames(of:));
/// JSON protegido (nil si el objeto no es serializable o lanza excepción).
+ (nullable NSData *)jsonData:(id)object NS_SWIFT_NAME(jsonData(_:));
/// NSKeyedArchiver protegido.
+ (nullable NSData *)archive:(id)object NS_SWIFT_NAME(archive(_:));
/// description protegida.
+ (NSString *)describe:(id)object NS_SWIFT_NAME(describe(_:));

/// Instala manejadores de cierre que escriben en `path` la causa y el último paso.
+ (void)installCrashHandlerAtPath:(NSString *)path NS_SWIFT_NAME(installCrashHandler(path:));
/// Anota el paso actual (se escribe en el fichero de cierre si la app muere).
+ (void)mark:(NSString *)step NS_SWIFT_NAME(mark(_:));
@end

NS_ASSUME_NONNULL_END
